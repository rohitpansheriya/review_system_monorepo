/**
 * invoiceGenerator.ts
 *
 * Generates clean, branded PDF Invoices / Payment Receipts using PDFKit.
 * Supports single-branch, multi-branch, online, and cash activations.
 */

import PDFDocument from "pdfkit";

export interface InvoiceBranchItem {
  name: string;
  address?: string;
  amount?: number;
}

export interface InvoiceData {
  invoiceNumber: string;
  businessCode?: string;
  dateStr: string;
  ownerName: string;
  brandName: string;
  ownerEmail: string;
  ownerPhone?: string;
  amount: number;
  paymentMode: "online" | "cash";
  paymentReference?: string;
  planTitle?: string;
  branches?: InvoiceBranchItem[];
}

/**
 * Builds a PDF Invoice as a Buffer to be attached to Brevo transactional emails.
 * @param {InvoiceData} data - Invoice fields.
 * @return {Promise<Buffer>} The generated PDF as a Buffer.
 */
export async function generateInvoicePdf(data: InvoiceData): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    try {
      const doc = new PDFDocument({size: "A4", margin: 40});
      const buffers: Buffer[] = [];

      doc.on("data", (chunk: Buffer) => buffers.push(chunk));
      doc.on("end", () => resolve(Buffer.concat(buffers)));
      doc.on("error", (err: Error) => reject(err));

      const primaryColor = "#4F46E5";
      const darkColor = "#1E293B";
      const grayColor = "#64748B";
      const lightBg = "#F8FAFC";

      // ── Header Background Banner ──────────────────────────────
      doc.rect(40, 40, 515, 70).fill(lightBg);
      doc.fillColor(primaryColor).fontSize(22).font("Helvetica-Bold").text("AppNexa", 55, 55);
      doc.fillColor(grayColor).fontSize(10).font("Helvetica").text("Smart Review Management System", 55, 82);

      // Invoice Title & Status
      doc.fillColor(darkColor).fontSize(14).font("Helvetica-Bold").text("INVOICE / RECEIPT", 380, 55, {align: "right", width: 160});
      doc.fillColor("#059669").fontSize(10).font("Helvetica-Bold").text("STATUS: PAID", 380, 75, {align: "right", width: 160});

      doc.moveDown(3);

      // ── Invoice Meta Info ──────────────────────────────────────
      const metaY = 125;
      doc.fillColor(darkColor).fontSize(10).font("Helvetica-Bold").text("Invoice No:", 40, metaY);
      doc.font("Helvetica").text(data.invoiceNumber, 110, metaY);

      if (data.businessCode) {
        doc.font("Helvetica-Bold").text("Client ID:", 40, metaY + 16);
        doc.font("Helvetica").text(data.businessCode, 110, metaY + 16);
      }

      const dateOffset = data.businessCode ? 32 : 16;
      doc.font("Helvetica-Bold").text("Invoice Date:", 40, metaY + dateOffset);
      doc.font("Helvetica").text(data.dateStr, 110, metaY + dateOffset);

      doc.font("Helvetica-Bold").text("Payment Mode:", 40, metaY + dateOffset + 16);
      doc.font("Helvetica").text(data.paymentMode === "cash" ? "Cash Collection" : "Online (Razorpay)", 125, metaY + dateOffset + 16);

      if (data.paymentReference) {
        doc.font("Helvetica-Bold").text("Reference:", 40, metaY + dateOffset + 32);
        doc.font("Helvetica").text(data.paymentReference, 110, metaY + dateOffset + 32);
      }

      // ── Seller Info ───────────────────────────────────────────
      const sellerX = 320;
      doc.fillColor(darkColor).fontSize(10).font("Helvetica-Bold").text("Issued By:", sellerX, metaY);
      doc.font("Helvetica").text("AppNexa Technologies", sellerX, metaY + 16);
      doc.fillColor(grayColor).text("support@appnexa.co.in", sellerX, metaY + 30);
      doc.text("https://appnexa.co.in", sellerX, metaY + 44);

      // ── Customer Details ──────────────────────────────────────
      const custY = metaY + 75;
      doc.rect(40, custY, 515, 60).fill("#F1F5F9");
      doc.fillColor(darkColor).fontSize(10).font("Helvetica-Bold").text("Billed To:", 55, custY + 10);
      doc.font("Helvetica-Bold").text(data.brandName, 55, custY + 24);
      doc.font("Helvetica").fillColor(grayColor).text(`Attn: ${data.ownerName} (${data.ownerEmail})`, 55, custY + 38);

      // ── Line Items Table ──────────────────────────────────────
      const tableY = custY + 75;
      doc.rect(40, tableY, 515, 24).fill(primaryColor);
      doc.fillColor("#FFFFFF").fontSize(9).font("Helvetica-Bold");
      doc.text("ITEM DESCRIPTION", 50, tableY + 7);
      doc.text("QTY", 370, tableY + 7, {width: 40, align: "center"});
      doc.text("RATE", 420, tableY + 7, {width: 50, align: "right"});
      doc.text("AMOUNT", 480, tableY + 7, {width: 65, align: "right"});

      let currentY = tableY + 30;

      const branchItems: InvoiceBranchItem[] = (data.branches && data.branches.length > 0) ?
        data.branches :
        [{name: data.brandName, amount: data.amount}];

      const ratePerBranch = branchItems.length > 0 ?
        (branchItems[0].amount || Math.round(data.amount / branchItems.length)) :
        1999;

      for (let i = 0; i < branchItems.length; i++) {
        const branch = branchItems[i];
        const itemAmount = branch.amount || ratePerBranch;
        const branchTitle = `AppNexa Pro Subscription (1-Year) — ${branch.name}`;

        doc.fillColor(darkColor).fontSize(9).font("Helvetica-Bold").text(branchTitle, 50, currentY, {width: 310});
        doc.fontSize(8).font("Helvetica").fillColor(grayColor).text(
          "Smart NFC & QR Standee, cloud review routing, negative feedback shield.",
          50,
          currentY + 13,
          {width: 310}
        );

        doc.fillColor(darkColor).fontSize(9).font("Helvetica").text("1", 370, currentY, {width: 40, align: "center"});
        doc.text(`₹${itemAmount.toLocaleString("en-IN")}`, 420, currentY, {width: 50, align: "right"});
        doc.font("Helvetica-Bold").text(`₹${itemAmount.toLocaleString("en-IN")}`, 480, currentY, {width: 65, align: "right"});

        currentY += 34;

        // Divider between items
        doc.strokeColor("#E2E8F0").lineWidth(0.5).moveTo(40, currentY - 4).lineTo(555, currentY - 4).stroke();
      }

      // ── Summary Totals ────────────────────────────────────────
      const summaryY = currentY + 10;
      doc.fillColor(grayColor).fontSize(10).font("Helvetica").text("Subtotal:", 380, summaryY, {width: 90, align: "right"});
      doc.fillColor(darkColor).text(`₹${data.amount.toLocaleString("en-IN")}`, 480, summaryY, {width: 65, align: "right"});

      doc.fillColor(grayColor).text("GST (0% Exempt):", 380, summaryY + 16, {width: 90, align: "right"});
      doc.fillColor(darkColor).text("₹0.00", 480, summaryY + 16, {width: 65, align: "right"});

      doc.rect(370, summaryY + 34, 185, 26).fill("#EEF2FF");
      doc.fillColor(primaryColor).fontSize(11).font("Helvetica-Bold").text("Total Paid:", 380, summaryY + 41, {width: 90, align: "right"});
      doc.text(`₹${data.amount.toLocaleString("en-IN")}`, 480, summaryY + 41, {width: 65, align: "right"});

      // ── Tax Exemption Disclaimer ──────────────────────────────
      const taxNoteY = summaryY + 75;
      doc.rect(40, taxNoteY, 515, 45).fill("#FEF3C7");
      doc.fillColor("#92400E").fontSize(8).font("Helvetica-Bold").text("TAX EXEMPTION & COMPLIANCE NOTE:", 50, taxNoteY + 8);
      doc.font("Helvetica").fontSize(8).text(
        "Billed under GST Threshold Exemption as per Section 22 of the CGST Act, 2017 (Aggregate turnover within exemption limit). No GST has been collected on this invoice.",
        50,
        taxNoteY + 20,
        {width: 495}
      );

      // ── Footer ────────────────────────────────────────────────
      const footerY = taxNoteY + 65;
      doc.fillColor(grayColor).fontSize(8).font("Helvetica").text("This is a computer-generated invoice and requires no physical signature.", 40, footerY, {align: "center", width: 515});
      doc.text("Thank you for choosing AppNexa to grow your business!", 40, footerY + 14, {align: "center", width: 515});

      doc.end();
    } catch (e) {
      reject(e);
    }
  });
}
