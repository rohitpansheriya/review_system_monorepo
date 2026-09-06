// lib/main.dart
// App entry point. Initialises Firebase, connects to emulators in debug mode,
// wires providers, and starts the GoRouter.
//
// KEY DESIGN: AppAuthProvider is created here as a StatefulWidget field so
// GoRouter can use it as refreshListenable — the router re-evaluates redirect
// every time auth state changes (sign-in, sign-out, deactivation).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'core/constants.dart';
import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'providers/commission_provider.dart';
import 'providers/enroll_provider.dart';
import 'providers/my_businesses_provider.dart';
import 'providers/owner_dashboard_provider.dart';
import 'providers/admin_dashboard_provider.dart';
import 'providers/profile_provider.dart';
import 'services/auth_service.dart';
import 'services/firestore_service.dart';
import 'services/places_service.dart';
import 'services/qr_stub_service.dart';
import 'services/storage_service.dart';
import 'screens/login/login_screen.dart';
import 'screens/enroll/enroll_screen.dart';
import 'screens/enroll/payment_screen.dart';
import 'screens/my_businesses/my_businesses_screen.dart';
import 'screens/owner/owner_dashboard_screen.dart';
import 'screens/admin/admin_dashboard_screen.dart';
import 'screens/business_detail/business_detail_screen.dart';
import 'screens/business_detail/business_edit_screen.dart';
import 'screens/commission/commission_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'widgets/app_splash_screen.dart';
import 'models/business_model.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // ── Connect to local Firebase Emulator Suite (in debug mode OR via --dart-define=USE_EMULATOR=true) ─
  const bool useEmulatorDefine = bool.fromEnvironment('USE_EMULATOR', defaultValue: false);
  final bool connectEmulators = useEmulatorDefine || kDebugMode;

  if (connectEmulators) {
    try {
      await FirebaseAuth.instance.useAuthEmulator(
        AppConstants.emulatorHost,
        AppConstants.emulatorAuthPort,
      );
      FirebaseFirestore.instance.useFirestoreEmulator(
        AppConstants.emulatorHost,
        AppConstants.emulatorFirestorePort,
      );
      FirebaseFunctions.instanceFor(region: 'asia-south1').useFunctionsEmulator(
        AppConstants.emulatorHost,
        AppConstants.emulatorFunctionsPort,
      );
      await FirebaseStorage.instance.useStorageEmulator(
        AppConstants.emulatorHost,
        AppConstants.emulatorStoragePort,
      );
      // ignore: avoid_print
      print('⚡ Firebase Emulator Suite connected (USE_EMULATOR=$useEmulatorDefine, kDebugMode=$kDebugMode)');
    } catch (e) {
      // ignore: avoid_print
      print('⚠️ Emulator connection failed: $e — using production Firebase');
    }
  }

  runApp(const ReviewSystemApp());
}

// ── StatefulWidget so we can own services + providers as long-lived fields ──
class ReviewSystemApp extends StatefulWidget {
  const ReviewSystemApp({super.key});

  @override
  State<ReviewSystemApp> createState() => _ReviewSystemAppState();
}

class _ReviewSystemAppState extends State<ReviewSystemApp> {
  // Services (singletons — no Firebase calls at construction time)
  final _authService      = AuthService();
  final _firestoreService = FirestoreService();
  final _storageService   = StorageService();
  final _placesService    = PlacesService();
  final _qrStubService    = QrStubService();

  late final AppAuthProvider _authProvider;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();

    // Create the auth provider first — it will be used as GoRouter's
    // refreshListenable so the router re-evaluates redirect on every
    // auth state change (sign-in, sign-out, claim change, deactivation).
    _authProvider = AppAuthProvider(
      authService:      _authService,
      firestoreService: _firestoreService,
    );

    _router = GoRouter(
      initialLocation: '/login',

      // ── This is the KEY FIX: AppAuthProvider IS the ChangeNotifier ────────
      // GoRouter calls addListener on this and re-runs redirect every time
      // _authProvider.notifyListeners() fires (after sign-in, sign-out, etc.)
      refreshListenable: _authProvider,

      redirect: (context, state) {
        final status = _authProvider.status;
        final loc    = state.matchedLocation;
        final isLoginPage = loc == '/login';

        // Still initialising — keep current location
        if (status == AuthStatus.unknown) return null;

        // Not authenticated → always go to login
        if (status == AuthStatus.unauthenticated ||
            status == AuthStatus.accessDenied) {
          return isLoginPage ? null : '/login';
        }

        // Authenticated + on login page → send to role home
        if (status == AuthStatus.authenticated && isLoginPage) {
          if (_authProvider.isAdmin) return '/admin';
          if (_authProvider.isOwner) return '/owner';
          return '/businesses';
        }

        return null;
      },

      routes: [
        GoRoute(path: '/login',      builder: (_, __) => const LoginScreen()),
        GoRoute(path: '/businesses', builder: (_, __) => const MyBusinessesScreen()),
        GoRoute(
          path: '/owner',
          builder: (_, state) => OwnerDashboardScreen(
            initialTab: state.uri.queryParameters['tab'],
          ),
        ),
        GoRoute(path: '/enroll',     builder: (_, __) => const EnrollScreen()),
        GoRoute(path: '/commission', builder: (_, __) => const CommissionScreen()),
        GoRoute(path: '/profile',    builder: (_, __) => const ProfileScreen()),
        GoRoute(
          path: '/enroll/payment/:businessId',
          builder: (context, state) {
            final bizId = state.pathParameters['businessId'] ?? '';
            return PaymentScreen(businessId: bizId);
          },
        ),
        GoRoute(
          path: '/enroll/payment/:businessId/:branchId',
          builder: (context, state) {
            final bizId = state.pathParameters['businessId'] ?? '';
            final branchId = state.pathParameters['branchId'] ?? '';
            return PaymentScreen(businessId: bizId, branchId: branchId);
          },
        ),
        GoRoute(
          path: '/business/:id',
          builder: (context, state) {
            final biz = state.extra;
            if (biz == null) {
              // Fallback when navigated without extra (e.g. direct URL).
              // Admin → admin dashboard, Employee → My Enrolled Businesses.
              return _authProvider.isAdmin
                  ? const AdminDashboardScreen()
                  : const MyBusinessesScreen();
            }
            return BusinessDetailScreen(business: biz as BusinessModel);
          },
        ),
        GoRoute(
          path: '/business/:id/edit',
          builder: (context, state) {
            final biz = state.extra;
            if (biz == null) {
              return _authProvider.isAdmin
                  ? const AdminDashboardScreen()
                  : const MyBusinessesScreen();
            }
            return BusinessEditScreen(business: biz as BusinessModel);
          },
        ),

        // ── Admin Dashboard (Doc 04 Admin Panel) ───────────────────────────
        GoRoute(
          path: '/admin',
          builder: (_, state) => AdminDashboardScreen(
            initialTab: state.uri.queryParameters['tab'],
          ),
        ),
      ],

      errorBuilder: (_, state) => Scaffold(
        body: Center(child: Text('Page not found: ${state.error}')),
      ),
    );
  }

  @override
  void dispose() {
    _authProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // ── App-level auth provider — share the SAME instance used by router ─
        ChangeNotifierProvider<AppAuthProvider>.value(value: _authProvider),

        // ── Screen-level providers ──────────────────────────────────────────
        ChangeNotifierProvider(
          create: (_) => EnrollProvider(
            firestoreService: _firestoreService,
            storageService:   _storageService,
            placesService:    _placesService,
            qrStubService:    _qrStubService,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => MyBusinessesProvider(firestoreService: _firestoreService),
        ),
        ChangeNotifierProvider(
          create: (_) => OwnerDashboardProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => AdminDashboardProvider(firestoreService: _firestoreService),
        ),
        ChangeNotifierProvider(
          create: (_) => CommissionProvider(firestoreService: _firestoreService),
        ),
        ChangeNotifierProvider(
          create: (_) => ProfileProvider(
            firestoreService: _firestoreService,
            storageService:   _storageService,
          ),
        ),

        // ── Expose services for direct reads / uploads / searches ───────────
        Provider<FirestoreService>.value(value: _firestoreService),
        Provider<StorageService>.value(value: _storageService),
        Provider<PlacesService>.value(value: _placesService),
      ],
      child: MaterialApp.router(
        title: 'Review System Panel',
        theme: AppTheme.light,
        routerConfig: _router,
        debugShowCheckedModeBanner: false,
        builder: (context, child) {
          final auth = context.watch<AppAuthProvider>();
          if (auth.status == AuthStatus.unknown) {
            return const AppSplashScreen(message: 'Loading AppNexa…');
          }
          return child ?? const SizedBox.shrink();
        },
      ),
    );
  }
}
