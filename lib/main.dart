import 'dart:async';
import 'dart:developer' as developer;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'data/models/sync_operation.dart';

import 'auth/workspace_access_resolution.dart';
import 'auth/workspace_access_service.dart';

import 'data/sync/sync_engine.dart';
import 'di/app_dependencies.dart';
import 'firebase_options.dart';
import 'presentation/sites/survey_sites_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (kReleaseMode) {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: const AndroidPlayIntegrityProvider(),
    );
  }

  final dependencies = AppDependencies.create();

  await dependencies.authService.initialize();

  // Remove any old anonymous session left by the previous implementation.
  final existingUser = dependencies.authService.currentUser;

  if (existingUser?.isAnonymous ?? false) {
    await dependencies.authService.signOut();
  }

  developer.log(
    'Firebase and application dependencies initialized. '
    'App Check release mode: $kReleaseMode',
    name: 'Application',
  );

  runApp(MyApp(dependencies: dependencies));
}

class MyApp extends StatelessWidget {
  const MyApp({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Collaborative Field Engineer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF245A8D)),
        useMaterial3: true,
      ),
      home: AuthenticationGate(dependencies: dependencies),
    );
  }
}

class AuthenticationGate extends StatefulWidget {
  const AuthenticationGate({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  State<AuthenticationGate> createState() {
    return _AuthenticationGateState();
  }
}

class _AuthenticationGateState extends State<AuthenticationGate>
    with WidgetsBindingObserver {
  final Connectivity _connectivity = Connectivity();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _authorizationExpiryTimer;

  String? _loadedUid;
  Future<WorkspaceAccessResolution>? _accessFuture;

  DateTime? _cachedAuthorizationExpiresAt;

  bool _wasOnline = false;
  bool _isRevalidating = false;
  bool _offlineAuthorizationExpired = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    unawaited(_startConnectivityMonitoring());
  }

  Future<void> _startConnectivityMonitoring() async {
    try {
      final initialResults = await _connectivity.checkConnectivity();
      _wasOnline = _hasConnection(initialResults);

      _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
        _handleConnectivityChanged,
        onError: (Object error, StackTrace stackTrace) {
          developer.log(
            'Access connectivity monitoring failed',
            name: 'Authentication',
            error: error,
            stackTrace: stackTrace,
          );
        },
      );
    } catch (error, stackTrace) {
      developer.log(
        'Could not start access connectivity monitoring',
        name: 'Authentication',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _handleConnectivityChanged(List<ConnectivityResult> results) {
    final isOnline = _hasConnection(results);
    final connectionWasRestored = !_wasOnline && isOnline;

    _wasOnline = isOnline;

    if (!connectionWasRestored) {
      return;
    }

    final user = widget.dependencies.authService.currentUser;

    if (user == null) {
      return;
    }

    developer.log(
      'Connectivity restored. Revalidating workspace membership.',
      name: 'Authentication',
    );

    _retryAccessCheck(user.uid, isAutomaticRevalidation: true);
  }

  bool _hasConnection(List<ConnectivityResult> results) {
    return results.any((result) => result != ConnectivityResult.none);
  }

  Future<WorkspaceAccessResolution> _loadAccess(String uid) {
    if (_loadedUid != uid || _accessFuture == null) {
      _cancelAuthorizationExpiryTimer();

      _loadedUid = uid;
      _isRevalidating = false;
      _offlineAuthorizationExpired = false;

      _accessFuture = widget.dependencies.workspaceAccessResolver.resolve(uid);
    }

    return _accessFuture!;
  }

  void _retryAccessCheck(String uid, {bool isAutomaticRevalidation = false}) {
    if (!mounted) {
      return;
    }

    _cancelAuthorizationExpiryTimer();

    setState(() {
      _loadedUid = uid;
      _isRevalidating = isAutomaticRevalidation;
      _offlineAuthorizationExpired = false;

      _accessFuture = widget.dependencies.workspaceAccessResolver.resolve(uid);
    });
  }

  void _scheduleAuthorizationExpiry(WorkspaceAccessResolution resolution) {
    if (!resolution.isOfflineCached) {
      _cancelAuthorizationExpiryTimer();
      return;
    }

    final verifiedAt = resolution.verifiedAt;

    if (verifiedAt == null) {
      _expireOfflineAuthorization();
      return;
    }

    final expiresAt = verifiedAt.toUtc().add(
      widget.dependencies.workspaceAccessResolver.maxOfflineAccessAge,
    );

    if (_cachedAuthorizationExpiresAt == expiresAt &&
        _authorizationExpiryTimer?.isActive == true) {
      return;
    }

    _authorizationExpiryTimer?.cancel();
    _cachedAuthorizationExpiresAt = expiresAt;

    final remainingTime = expiresAt.difference(DateTime.now().toUtc());

    if (remainingTime <= Duration.zero) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _expireOfflineAuthorization();
      });

      return;
    }

    developer.log(
      'Offline authorization expires at '
      '${expiresAt.toIso8601String()}',
      name: 'Authentication',
    );

    _authorizationExpiryTimer = Timer(
      remainingTime,
      _expireOfflineAuthorization,
    );
  }

  void _expireOfflineAuthorization() {
    if (!mounted || _offlineAuthorizationExpired) {
      return;
    }

    _cancelAuthorizationExpiryTimer();

    developer.log(
      'Offline authorization expired while the application was open.',
      name: 'Authentication',
    );

    setState(() {
      _offlineAuthorizationExpired = true;
    });
  }

  void _cancelAuthorizationExpiryTimer() {
    _authorizationExpiryTimer?.cancel();
    _authorizationExpiryTimer = null;
    _cachedAuthorizationExpiresAt = null;
  }

  void _checkAuthorizationExpiry() {
    final expiresAt = _cachedAuthorizationExpiresAt;

    if (expiresAt == null || _offlineAuthorizationExpired) {
      return;
    }

    final hasExpired = !DateTime.now().toUtc().isBefore(expiresAt);

    if (hasExpired) {
      _expireOfflineAuthorization();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAuthorizationExpiry();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _authorizationExpiryTimer?.cancel();
    _authorizationExpiryTimer = null;

    unawaited(_connectivitySubscription?.cancel());
    _connectivitySubscription = null;

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: widget.dependencies.authService.authStateChanges,
      initialData: widget.dependencies.authService.currentUser,
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting &&
            authSnapshot.data == null) {
          return const _LoadingScreen(message: 'Checking authentication...');
        }

        final user = authSnapshot.data;

        if (user == null) {
          _cancelAuthorizationExpiryTimer();

          return GoogleSignInScreen(dependencies: widget.dependencies);
        }

        if (_offlineAuthorizationExpired) {
          return WorkspaceAccessErrorScreen(
            dependencies: widget.dependencies,
            user: user,
            error: StateError(
              'Offline authorization expired after the maximum '
              '24-hour access period.',
            ),
            onRetry: () => _retryAccessCheck(user.uid),
          );
        }

        return FutureBuilder<WorkspaceAccessResolution>(
          future: _loadAccess(user.uid),
          builder: (context, accessSnapshot) {
            if (accessSnapshot.connectionState == ConnectionState.waiting) {
              return _LoadingScreen(
                message: _isRevalidating
                    ? 'Connection restored. Revalidating workspace '
                          'membership...'
                    : 'Checking workspace access for '
                          '${user.email ?? user.uid}...',
              );
            }

            if (accessSnapshot.hasError) {
              _cancelAuthorizationExpiryTimer();

              return WorkspaceAccessErrorScreen(
                dependencies: widget.dependencies,
                user: user,
                error: accessSnapshot.error!,
                onRetry: () => _retryAccessCheck(user.uid),
              );
            }

            final resolution = accessSnapshot.data;

            if (resolution == null) {
              _cancelAuthorizationExpiryTimer();

              return WorkspaceAccessErrorScreen(
                dependencies: widget.dependencies,
                user: user,
                error: StateError(
                  'Workspace access resolution returned no result.',
                ),
                onRetry: () => _retryAccessCheck(user.uid),
              );
            }

            switch (resolution.status) {
              case WorkspaceAccessResolutionStatus.granted:
                final access = resolution.access;

                if (access == null) {
                  _cancelAuthorizationExpiryTimer();

                  return WorkspaceAccessErrorScreen(
                    dependencies: widget.dependencies,
                    user: user,
                    error: StateError(
                      'Access was granted without workspace details.',
                    ),
                    onRetry: () => _retryAccessCheck(user.uid),
                  );
                }

                _scheduleAuthorizationExpiry(resolution);

                return SyncDashboardScreen(
                  dependencies: widget.dependencies,
                  user: user,
                  access: access,
                  accessResolution: resolution,
                );

              case WorkspaceAccessResolutionStatus.unauthorized:
                _cancelAuthorizationExpiryTimer();

                return UnauthorizedScreen(
                  dependencies: widget.dependencies,
                  user: user,
                  onRetry: () => _retryAccessCheck(user.uid),
                );

              case WorkspaceAccessResolutionStatus.unavailable:
                _cancelAuthorizationExpiryTimer();

                return WorkspaceAccessErrorScreen(
                  dependencies: widget.dependencies,
                  user: user,
                  error:
                      resolution.error ??
                      StateError(
                        'Workspace access could not be verified online, '
                        'and no matching cached authorization exists.',
                      ),
                  onRetry: () => _retryAccessCheck(user.uid),
                );
            }
          },
        );
      },
    );
  }
}

class GoogleSignInScreen extends StatefulWidget {
  const GoogleSignInScreen({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  State<GoogleSignInScreen> createState() => _GoogleSignInScreenState();
}

class _GoogleSignInScreenState extends State<GoogleSignInScreen> {
  bool _isSigningIn = false;
  String? _errorMessage;

  Future<void> _signIn() async {
    if (_isSigningIn) {
      return;
    }

    setState(() {
      _isSigningIn = true;
      _errorMessage = null;
    });

    try {
      await widget.dependencies.authService.signInWithGoogle();
    } catch (error, stackTrace) {
      developer.log(
        'Google authentication failed',
        name: 'Authentication',
        error: error,
        stackTrace: stackTrace,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'Google sign-in failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSigningIn = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Collaborative Field Engineer')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.engineering,
                        size: 72,
                        color: Color(0xFF245A8D),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Secure workspace access',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Sign in with your authorized Google account to '
                        'access the field engineering workspace.',
                        textAlign: TextAlign.center,
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 20),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      FilledButton.icon(
                        onPressed: _isSigningIn ? null : _signIn,
                        icon: _isSigningIn
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.login),
                        label: Text(
                          _isSigningIn
                              ? 'Signing in...'
                              : 'Sign in with Google',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class UnauthorizedScreen extends StatelessWidget {
  const UnauthorizedScreen({
    required this.dependencies,
    required this.user,
    required this.onRetry,
    super.key,
  });

  final AppDependencies dependencies;
  final User user;
  final VoidCallback onRetry;

  Future<void> _signOut() async {
    await dependencies.authService.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Workspace access required')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.lock_outline,
                        color: Colors.orange,
                        size: 72,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Account not authorized',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        user.email ?? 'Google account',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Add this Firebase UID to the workspace membership '
                        'list before using the application:',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      SelectableText(
                        user.uid,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      SelectableText(
                        'workspaceMembers/'
                        '${AppDependencies.workspaceId}/'
                        '${user.uid}/role',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Use viewer, editor, or admin as the role value. '
                        'Only administrators can synchronize data under '
                        'the current security policy.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Check access again'),
                      ),
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: _signOut,
                        icon: const Icon(Icons.logout),
                        label: const Text('Sign out'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WorkspaceAccessErrorScreen extends StatelessWidget {
  const WorkspaceAccessErrorScreen({
    required this.dependencies,
    required this.user,
    required this.error,
    required this.onRetry,
    super.key,
  });

  final AppDependencies dependencies;
  final User user;
  final Object error;
  final VoidCallback onRetry;

  Future<void> _signOut() async {
    await dependencies.authService.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final errorMessage = error.toString();

    final authorizationExpired = errorMessage.toLowerCase().contains('expired');

    final title = authorizationExpired
        ? 'Offline authorization expired'
        : 'Could not check workspace access';

    final description = authorizationExpired
        ? 'Your previously verified offline authorization is older than '
              '24 hours. Connect to the internet and try again so your '
              'workspace membership can be verified.'
        : errorMessage;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          authorizationExpired
              ? 'Authorization expired'
              : 'Access check failed',
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        authorizationExpired
                            ? Icons.timer_off_outlined
                            : Icons.error_outline,
                        color: authorizationExpired
                            ? Colors.orange
                            : Theme.of(context).colorScheme.error,
                        size: 72,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${user.email ?? user.uid}\n\n$description',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      if (authorizationExpired)
                        const Text(
                          'Offline data remains stored locally, but the '
                          'application cannot reopen the workspace until '
                          'authorization is verified online.',
                          textAlign: TextAlign.center,
                        ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.wifi_find),
                        label: Text(
                          authorizationExpired ? 'Verify online' : 'Try again',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: _signOut,
                        icon: const Icon(Icons.logout),
                        label: const Text('Sign out'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                Text(message, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SyncDashboardScreen extends StatefulWidget {
  const SyncDashboardScreen({
    required this.dependencies,
    required this.user,
    required this.access,
    required this.accessResolution,
    super.key,
  });

  final AppDependencies dependencies;
  final User user;
  final WorkspaceAccess access;
  final WorkspaceAccessResolution accessResolution;

  @override
  State<SyncDashboardScreen> createState() => _SyncDashboardScreenState();
}

class _SyncDashboardScreenState extends State<SyncDashboardScreen> {
  bool _isSynchronizing = false;
  bool _isRetrying = false;
  bool _isLoadingDashboard = true;
  bool _isSigningOut = false;

  DateTime? _lastSuccessfulSyncAt;

  Map<SyncQueueStatus, int> _statusCounts = {
    for (final status in SyncQueueStatus.values) status: 0,
  };

  String _statusMessage =
      'Firebase is ready for secure remote synchronization.';

  bool get _canSynchronize {
    return widget.accessResolution.isOnlineVerified &&
        widget.access.canSynchronize;
  }

  bool get _isOfflineSession {
    return widget.accessResolution.isOfflineCached;
  }

  DateTime? get _authorizationVerifiedAt {
    return widget.accessResolution.verifiedAt;
  }

  DateTime? get _authorizationExpiresAt {
    final verifiedAt = _authorizationVerifiedAt;

    if (verifiedAt == null) {
      return null;
    }

    return verifiedAt.add(
      widget.dependencies.workspaceAccessResolver.maxOfflineAccessAge,
    );
  }

  String get _authorizationSourceLabel {
    return _isOfflineSession
        ? 'Verified local authorization cache'
        : 'Firebase online verification';
  }

  @override
  void initState() {
    super.initState();

    final coordinator = widget.dependencies.automaticSyncCoordinator;

    if (_canSynchronize) {
      coordinator.onSyncCompleted = _handleAutomaticSyncCompleted;
      coordinator.onSyncFailed = _handleAutomaticSyncFailed;
      unawaited(_startAutomaticSynchronization());
    } else if (_isOfflineSession) {
      _statusMessage =
          'Offline access granted using previously verified authorization. '
          'Remote synchronization is locked until workspace membership '
          'is revalidated online.';
    } else {
      _statusMessage =
          'Workspace access granted in read-only mode. '
          'Synchronization requires an online-verified admin role.';
    }

    unawaited(_refreshDashboard());
  }

  @override
  void didUpdateWidget(covariant SyncDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    final previouslyAllowed =
        oldWidget.accessResolution.isOnlineVerified &&
        oldWidget.access.canSynchronize;

    if (!previouslyAllowed && _canSynchronize) {
      final coordinator = widget.dependencies.automaticSyncCoordinator;

      coordinator.onSyncCompleted = _handleAutomaticSyncCompleted;
      coordinator.onSyncFailed = _handleAutomaticSyncFailed;

      _statusMessage =
          'Workspace membership was revalidated successfully. '
          'Synchronization is now available.';

      unawaited(_startAutomaticSynchronization());
      return;
    }

    if (previouslyAllowed && !_canSynchronize) {
      _statusMessage = _isOfflineSession
          ? 'Connection lost. Local access remains available, but '
                'synchronization is locked until online revalidation.'
          : 'Synchronization is unavailable for the current workspace role.';

      unawaited(widget.dependencies.automaticSyncCoordinator.dispose());
    }
  }

  Future<void> _startAutomaticSynchronization() async {
    try {
      await widget.dependencies.automaticSyncCoordinator.start();
    } catch (error, stackTrace) {
      developer.log(
        'Could not start automatic synchronization',
        name: 'Application',
        error: error,
        stackTrace: stackTrace,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _statusMessage =
            'Automatic synchronization could not be started: $error';
      });
    }
  }

  void _handleAutomaticSyncCompleted(SyncBatchResult result) {
    unawaited(_completeAutomaticSynchronization(result));
  }

  Future<void> _completeAutomaticSynchronization(SyncBatchResult result) async {
    await _refreshDashboard();

    if (!mounted) {
      return;
    }

    setState(() {
      _isSynchronizing = false;
      _statusMessage = _formatResult(
        result,
        prefix: 'Automatic synchronization completed.',
      );
    });
  }

  void _handleAutomaticSyncFailed(Object error, StackTrace stackTrace) {
    developer.log(
      'Automatic synchronization failed',
      name: 'Application',
      error: error,
      stackTrace: stackTrace,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isSynchronizing = false;
      _statusMessage = 'Automatic synchronization failed: $error';
    });

    unawaited(_refreshDashboard());
  }

  Future<void> _refreshDashboard() async {
    if (mounted) {
      setState(() {
        _isLoadingDashboard = true;
      });
    }

    try {
      final counts = await widget.dependencies.syncQueue.getStatusCounts();

      final lastSuccessfulSyncAt = await widget.dependencies.syncQueue
          .getLastSuccessfulSyncAt();

      if (!mounted) {
        return;
      }

      setState(() {
        _statusCounts = counts;
        _lastSuccessfulSyncAt = lastSuccessfulSyncAt;
        _isLoadingDashboard = false;
      });
    } catch (error, stackTrace) {
      developer.log(
        'Could not refresh sync dashboard',
        name: 'Application',
        error: error,
        stackTrace: stackTrace,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingDashboard = false;
        _statusMessage = 'Could not refresh synchronization status: $error';
      });
    }
  }

  Future<void> _synchronize() async {
    if (_isSynchronizing || !_canSynchronize) {
      return;
    }

    final coordinator = widget.dependencies.automaticSyncCoordinator;

    if (!coordinator.isOnline) {
      setState(() {
        _statusMessage =
            'Device is offline. Pending operations will '
            'synchronize when connectivity returns.';
      });

      return;
    }

    setState(() {
      _isSynchronizing = true;
      _statusMessage = 'Synchronizing pending operations...';
    });

    try {
      final result = await coordinator.synchronizeNow();

      await _refreshDashboard();

      if (!mounted) {
        return;
      }

      setState(() {
        _statusMessage = _formatResult(
          result,
          prefix: 'Manual synchronization completed.',
        );
      });
    } catch (error, stackTrace) {
      developer.log(
        'Synchronization failed',
        name: 'Application',
        error: error,
        stackTrace: stackTrace,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _statusMessage = 'Synchronization failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSynchronizing = false;
        });
      }
    }
  }

  Future<void> _retryFailedOperations() async {
    if (_isSynchronizing || _isRetrying || !_canSynchronize) {
      return;
    }

    setState(() {
      _isRetrying = true;
      _statusMessage = 'Preparing failed operations for retry...';
    });

    try {
      final failedOperations = await widget.dependencies.syncQueue
          .getOperationsByStatus(SyncQueueStatus.failed);

      if (failedOperations.isEmpty) {
        await _refreshDashboard();

        if (!mounted) {
          return;
        }

        setState(() {
          _statusMessage = 'There are no failed operations to retry.';
        });

        return;
      }

      for (final operation in failedOperations) {
        await widget.dependencies.syncQueue.runTransaction((transaction) async {
          await widget.dependencies.syncQueue.retryFailedOperation(
            operation.operationId,
            executor: transaction,
          );

          await widget.dependencies.entitySyncStatusUpdater.refreshEntityStatus(
            entityType: operation.entityType,
            entityId: operation.entityId,
            executor: transaction,
          );
        });
      }

      await _refreshDashboard();

      if (!mounted) {
        return;
      }

      final coordinator = widget.dependencies.automaticSyncCoordinator;

      if (!coordinator.isOnline) {
        setState(() {
          _statusMessage =
              '${failedOperations.length} failed operations '
              'returned to the pending queue. They will '
              'synchronize when connectivity returns.';
        });

        return;
      }

      setState(() {
        _statusMessage =
            '${failedOperations.length} failed operations '
            'returned to the pending queue.';
      });

      await _synchronize();
    } catch (error, stackTrace) {
      developer.log(
        'Could not retry failed operations',
        name: 'Application',
        error: error,
        stackTrace: stackTrace,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _statusMessage = 'Could not retry failed operations: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRetrying = false;
        });
      }
    }
  }

  Future<void> _openSurveySites() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SurveySitesScreen(dependencies: widget.dependencies),
      ),
    );

    if (mounted) {
      await _refreshDashboard();
    }
  }

  Future<void> _signOut() async {
    if (_isSigningOut) {
      return;
    }

    setState(() {
      _isSigningOut = true;
    });

    try {
      await widget.dependencies.automaticSyncCoordinator.dispose();
      await widget.dependencies.authService.signOut();
    } catch (error, stackTrace) {
      developer.log(
        'Sign-out failed',
        name: 'Authentication',
        error: error,
        stackTrace: stackTrace,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _statusMessage = 'Could not sign out: $error';
        _isSigningOut = false;
      });
    }
  }

  String _formatResult(SyncBatchResult result, {required String prefix}) {
    return '$prefix\n'
        'Processed ${result.processed}: '
        '${result.succeeded} succeeded, '
        '${result.retried} scheduled for retry, '
        '${result.conflicted} conflicted, '
        '${result.failed} failed.';
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return 'Never';
    }

    final localValue = value.toLocal();

    String twoDigits(int number) {
      return number.toString().padLeft(2, '0');
    }

    return '${localValue.year}-'
        '${twoDigits(localValue.month)}-'
        '${twoDigits(localValue.day)} '
        '${twoDigits(localValue.hour)}:'
        '${twoDigits(localValue.minute)}';
  }

  int _countFor(SyncQueueStatus status) {
    return _statusCounts[status] ?? 0;
  }

  @override
  void dispose() {
    final coordinator = widget.dependencies.automaticSyncCoordinator;

    coordinator.onSyncCompleted = null;
    coordinator.onSyncFailed = null;

    if (_canSynchronize) {
      unawaited(coordinator.dispose());
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final coordinator = widget.dependencies.automaticSyncCoordinator;
    final isBusy = _isSynchronizing || _isRetrying || _isSigningOut;
    final failedCount = _countFor(SyncQueueStatus.failed);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Collaborative Field Engineer'),
        actions: [
          IconButton(
            onPressed: _isLoadingDashboard ? null : _refreshDashboard,
            tooltip: 'Refresh status',
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: isBusy ? null : _signOut,
            tooltip: 'Sign out',
            icon: _isSigningOut
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshDashboard,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundImage: widget.user.photoURL == null
                        ? null
                        : NetworkImage(widget.user.photoURL!),
                    child: widget.user.photoURL == null
                        ? const Icon(Icons.person)
                        : null,
                  ),
                  title: Text(
                    widget.user.displayName ??
                        widget.user.email ??
                        'Authenticated user',
                  ),
                  subtitle: Text(
                    '${widget.user.email ?? widget.user.uid}\n'
                    'Workspace role: ${widget.access.role.name}\n'
                    'Access source: $_authorizationSourceLabel',
                  ),
                  isThreeLine: false,
                  trailing: Icon(
                    _canSynchronize
                        ? Icons.admin_panel_settings
                        : Icons.visibility,
                    color: _canSynchronize ? Colors.green : Colors.blue,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Icon(
                coordinator.isOnline ? Icons.cloud_done : Icons.cloud_off,
                color: coordinator.isOnline ? Colors.green : Colors.orange,
                size: 64,
              ),
              const SizedBox(height: 12),
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                coordinator.isOnline
                    ? 'Connection: online'
                    : 'Connection: offline',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: coordinator.isOnline
                      ? Colors.green.shade700
                      : Colors.orange.shade800,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Synchronization status',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (_isLoadingDashboard)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                )
              else
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _StatusCard(
                      label: 'Pending',
                      count: _countFor(SyncQueueStatus.pending),
                      icon: Icons.schedule,
                      color: Colors.orange,
                    ),
                    _StatusCard(
                      label: 'Processing',
                      count: _countFor(SyncQueueStatus.processing),
                      icon: Icons.sync,
                      color: Colors.blue,
                    ),
                    _StatusCard(
                      label: 'Synced',
                      count: _countFor(SyncQueueStatus.synced),
                      icon: Icons.cloud_done,
                      color: Colors.green,
                    ),
                    _StatusCard(
                      label: 'Failed',
                      count: failedCount,
                      icon: Icons.error_outline,
                      color: Colors.red,
                    ),
                    _StatusCard(
                      label: 'Conflicts',
                      count: _countFor(SyncQueueStatus.conflict),
                      icon: Icons.warning_amber,
                      color: Colors.deepOrange,
                    ),
                  ],
                ),
              const SizedBox(height: 20),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Last successful sync'),
                  subtitle: Text(_formatDateTime(_lastSuccessfulSyncAt)),
                ),
              ),
              if (!_canSynchronize) ...[
                const SizedBox(height: 16),
                Card(
                  color: _isOfflineSession
                      ? Colors.orange.withValues(alpha: 0.08)
                      : Colors.blue.withValues(alpha: 0.08),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _isOfflineSession
                                  ? Icons.offline_pin_outlined
                                  : Icons.info_outline,
                              color: _isOfflineSession
                                  ? Colors.orange.shade800
                                  : Colors.blue.shade700,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _isOfflineSession
                                    ? 'Offline authorization active'
                                    : 'Read-only workspace access',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _isOfflineSession
                              ? 'Local work is available using previously verified '
                                    'authorization. Firebase synchronization remains locked '
                                    'until workspace membership is revalidated online.'
                              : 'Your workspace role can view local data but cannot upload, '
                                    'retry, or synchronize Firebase operations.',
                        ),
                        if (_isOfflineSession) ...[
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 8),
                          _AuthorizationDetail(
                            label: 'Last verified',
                            value: _formatDateTime(_authorizationVerifiedAt),
                            icon: Icons.verified_user_outlined,
                          ),
                          const SizedBox(height: 10),
                          _AuthorizationDetail(
                            label: 'Offline access expires',
                            value: _formatDateTime(_authorizationExpiresAt),
                            icon: Icons.timer_outlined,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Offline authorization is valid for a maximum of 24 hours.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Colors.orange.shade900,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Card(
                child: ListTile(
                  onTap: isBusy ? null : _openSurveySites,
                  leading: const CircleAvatar(child: Icon(Icons.map_outlined)),
                  title: const Text(
                    'Survey Sites',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'View locally stored sites and their observations',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: isBusy || !_canSynchronize ? null : _synchronize,
                icon: _isSynchronizing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                label: Text(
                  _isSynchronizing ? 'Synchronizing...' : 'Synchronize now',
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: isBusy || !_canSynchronize || failedCount == 0
                    ? null
                    : _retryFailedOperations,
                icon: _isRetrying
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.restart_alt),
                label: Text(
                  _isRetrying
                      ? 'Preparing retries...'
                      : 'Retry failed ($failedCount)',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthorizationDetail extends StatelessWidget {
  const _AuthorizationDetail({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
  });

  final String label;
  final int count;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final availableWidth = MediaQuery.sizeOf(context).width - 52;
    final cardWidth = availableWidth / 2;

    return SizedBox(
      width: cardWidth,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 12),
              Text(
                '$count',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}
