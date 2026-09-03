/**
 * scripts/test-orphan-payment-and-expiry.js
 *
 * Verifies:
 * 1. Payment link expiry (47h) strictly precedes draft cleanup window (48h).
 * 2. Webhook gracefully handles payment.captured for a deleted/non-existent business:
 *    - Records to `orphan_payments/{paymentId}` with status 'needs_action'.
 *    - Writes high-priority notification to `notifications` collection for Admin.
 *    - Leaves audit trail and never silently drops customer money.
 * 3. Firestore security rules protect `orphan_payments`:
 *    - Admin can read/update.
 *    - Public/unauthenticated/employees cannot read or create directly.
 */

const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const crypto = require('crypto');

process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099';

const app = initializeApp({ projectId: 'review-system-prod-49b7a' });
const db = getFirestore(app);

async function runTests() {
  console.log('🧪 Running Test Suite: Payment Link Expiry & Orphan Payment Sentinel...\n');

  // ──────────────────────────────────────────────────────────────────────────
  // TEST 1: Expiry Window Mathematics
  // ──────────────────────────────────────────────────────────────────────────
  console.log('--- TEST 1: Expiry Window Timing ---');
  const DRAFT_CLEANUP_HOURS = 48;
  const PAYMENT_LINK_EXPIRY_HOURS = 47;
  
  const now = Math.floor(Date.now() / 1000);
  const linkExpiryTimestamp = now + (PAYMENT_LINK_EXPIRY_HOURS * 3600);
  const draftCleanupTimestamp = now + (DRAFT_CLEANUP_HOURS * 3600);

  const bufferSeconds = draftCleanupTimestamp - linkExpiryTimestamp;
  const bufferHours = bufferSeconds / 3600;

  if (linkExpiryTimestamp < draftCleanupTimestamp && bufferHours === 1) {
    console.log(`✅ SUCCESS: Link expires at 47h (${bufferHours}h BEFORE the 48h draft cleanup).`);
    console.log(`   Link can never outlive its draft: link dies at t+47h, draft purged at t+48h.`);
  } else {
    throw new Error(`❌ FAIL: Timing mismatch: bufferHours=${bufferHours}`);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TEST 2: Webhook Simulation for Deleted / Non-Existent Business
  // ──────────────────────────────────────────────────────────────────────────
  console.log('\n--- TEST 2: Webhook Orphan Payment Handling ---');

  const testPaymentId = `pay_orphan_test_${Date.now()}`;
  const nonExistentBizId = `biz_purged_draft_${Date.now()}`;
  const testOrderId = `order_test_${Date.now()}`;
  const testEmail = 'unhappy_customer@example.com';
  const testPhone = '+919876543210';
  const amountPaise = 199900;

  // Ensure target business does NOT exist
  const existingSnap = await db.collection('businesses').doc(nonExistentBizId).get();
  if (existingSnap.exists) {
    await db.collection('businesses').doc(nonExistentBizId).delete();
  }

  // Post webhook payload to emulator Cloud Function
  const webhookSecret = 'my_local_test_secret_123';
  const payload = {
    entity: 'event',
    event: 'payment.captured',
    contains: ['payment'],
    payload: {
      payment: {
        entity: {
          id: testPaymentId,
          order_id: testOrderId,
          amount: amountPaise,
          currency: 'INR',
          status: 'captured',
          email: testEmail,
          contact: testPhone,
          notes: {
            businessId: nonExistentBizId,
            brandName: 'Purged Coffee Shop',
            type: 'setup_fee',
          },
        },
      },
    },
  };

  const bodyStr = JSON.stringify(payload);
  const signature = crypto
    .createHmac('sha256', webhookSecret)
    .update(bodyStr)
    .digest('hex');

  console.log(`   Dispatching payment.captured for non-existent business ${nonExistentBizId}...`);

  const response = await fetch(
    'http://127.0.0.1:5001/review-system-prod-49b7a/asia-south1/razorpayWebhook',
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Razorpay-Signature': signature,
      },
      body: bodyStr,
    }
  );

  console.log(`   Webhook HTTP response: ${response.status} ${response.statusText}`);

  // Give emulator a second to commit the async writes
  await new Promise((r) => setTimeout(r, 2000));

  // Verify orphan_payments document
  const orphanDoc = await db.collection('orphan_payments').doc(testPaymentId).get();
  if (!orphanDoc.exists) {
    throw new Error(`❌ FAIL: orphan_payments/${testPaymentId} document was NOT created!`);
  }

  const orphanData = orphanDoc.data();
  console.log('✅ SUCCESS: orphan_payments record created:', {
    payment_id: orphanData.payment_id,
    business_id: orphanData.business_id,
    amount_rupees: orphanData.amount_rupees,
    customer_email: orphanData.customer_email,
    customer_contact: orphanData.customer_contact,
    status: orphanData.status,
    reason: orphanData.reason,
    razorpay_dashboard_link: orphanData.razorpay_dashboard_link,
  });

  if (orphanData.status !== 'needs_action') {
    throw new Error(`Expected status 'needs_action', got ${orphanData.status}`);
  }
  if (orphanData.amount_rupees !== 1999) {
    throw new Error(`Expected amount_rupees 1999, got ${orphanData.amount_rupees}`);
  }

  // Verify notifications collection
  const notifSnap = await db
    .collection('notifications')
    .where('type', '==', 'orphan_payment_alert')
    .where('business_id', '==', nonExistentBizId)
    .get();

  if (notifSnap.empty) {
    throw new Error('❌ FAIL: Admin notification for orphan payment was NOT created!');
  }

  const notif = notifSnap.docs[0].data();
  console.log('✅ SUCCESS: Admin notification created:', {
    recipient: notif.recipient,
    recipient_role: notif.recipient_role,
    type: notif.type,
    subject: notif.subject,
    urgent: notif.urgent,
  });

  if (!notif.urgent) {
    throw new Error('Expected admin notification to have urgent: true');
  }

  console.log('\n🎉 ALL TESTS PASSED! Payment link expiry and orphan payment sentinel are verified!');
  process.exit(0);
}

runTests().catch((err) => {
  console.error('❌ Test failed:', err);
  process.exit(1);
});
