import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../screens/cognitive_load_screen.dart';
import '../screens/hazard_screen.dart';
import '../services/bluetooth_chat_service.dart';
import '../screens/chatbot_screen.dart';
import '../screens/crash_triage_screen.dart';
import '../screens/near_miss_screen.dart';
import '../screens/user_model.dart';
import '../screens/pothole_screen.dart';

// ─── Feature Data Model ───────────────────────────────────────────────────────

class FeatureData {
  final String id;
  final String title;
  final String subtitle;
  final String description;
  final IconData icon;
  final Color iconColor;
  final List<Color> gradientColors;
  final List<String> tags;
  final bool isLive;
  final bool isBuilt;

  const FeatureData({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
    required this.iconColor,
    required this.gradientColors,
    required this.tags,
    required this.isLive,
    required this.isBuilt,
  });
}

// ─── All Features List ────────────────────────────────────────────────────────

const List<FeatureData> kAllFeatures = [
  FeatureData(
    id: 'cognitive',
    title: 'Cognitive Load',
    subtitle: 'Monitor',
    description: 'AI-powered fatigue & distraction detection via front camera',
    icon: Icons.psychology_outlined,
    iconColor: Color(0xFF00E5CC),
    gradientColors: [Color(0xFF00E5CC), Color(0xFF0A84FF)],
    tags: ['ML Kit', 'Face Mesh', 'TFLite'],
    isLive: true,
    isBuilt: true,
  ),
  FeatureData(
    id: 'ble',
    title: 'WiFi Mesh',
    subtitle: 'Hazard + Chat',
    description: 'Peer-to-peer offline hazard sharing & group chat over WiFi',
    icon: Icons.hub_outlined,
    iconColor: Color(0xFFBF5AF2),
    gradientColors: [Color(0xFFBF5AF2), Color(0xFF5E5CE6)],
    tags: ['UDP', 'GPS', 'Chat'],
    isLive: true,
    isBuilt: true,
  ),
  FeatureData(
    id: 'near_miss',
    title: 'Near-Miss',
    subtitle: 'Reconstruction',
    description: 'IMU sensor fusion + map replay of incident events',
    icon: Icons.route_outlined,
    iconColor: Color(0xFFFF9F0A),
    gradientColors: [Color(0xFFFF9F0A), Color(0xFFFF6B00)],
    tags: ['Accelerometer', 'Gyroscope', 'Maps'],
    isLive: true,
    isBuilt: true,
  ),
  FeatureData(
    id: 'crash',
    title: 'Crash Triage',
    subtitle: 'Protocol',
    description: 'Automatic crash detection with emergency SOS alerts',
    icon: Icons.emergency_outlined,
    iconColor: Color(0xFFFF3B30),
    gradientColors: [Color(0xFFFF3B30), Color(0xFFFF6B30)],
    tags: ['IMU', 'GPS', 'SMS/Call'],
    isLive: true,
    isBuilt: true,
  ),
  FeatureData(
    id: 'chatbot',
    title: 'Road Safety',
    subtitle: 'Chatbot',
    description: 'Context-aware AI assistant with offline fallback mode',
    icon: Icons.smart_toy_outlined,
    iconColor: Color(0xFF30D158),
    gradientColors: [Color(0xFF30D158), Color(0xFF00C7BE)],
    tags: ['Gemini AI', 'Voice', 'Offline'],
    isLive: false,
    isBuilt: true,
  ),
  FeatureData(
    id: 'pothole',
    title: 'Voice Pothole',
    subtitle: 'Detection',
    description: 'Say "pothole" while driving to pin red dots on the map',
    icon: Icons.warning_amber_rounded,
    iconColor: Color(0xFFFF3B30),
    gradientColors: [Color(0xFFFF3B30), Color(0xFFFF6B30)],
    tags: ['Voice', 'GPS', 'Maps'],
    isLive: true,
    isBuilt: true,
  ),
];

// ─── Login Screen ─────────────────────────────────────────────────────────────

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _nameCtrl  = TextEditingController();
  bool _obscurePass = true;
  bool _isLoading   = false;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  UserModel _buildUser() {
    final email = _emailCtrl.text.trim();
    final name  = _nameCtrl.text.trim();
    final displayName = name.isNotEmpty ? name : email.split('@').first;
    return UserModel(email: email, displayName: displayName);
  }

  void _login() async {
    if (_emailCtrl.text.isEmpty || _passCtrl.text.isEmpty) return;
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    setState(() => _isLoading = false);
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, anim, __) => IntroScreen(user: _buildUser()),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  void _googleLogin() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, anim, __) => IntroScreen(
          user: UserModel(email: 'user@gmail.com', displayName: 'Google User'),
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      color: const Color(0xFF00E5CC).withValues(alpha: 0.08),
                      border: Border.all(
                        color: const Color(0xFF00E5CC).withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      color: Color(0xFF00E5CC),
                      size: 40,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    'GuardianDrive',
                    style: GoogleFonts.inter(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.6,
                    ),
                  ),
                ),
                Center(
                  child: Text(
                    'AI-powered road safety platform',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: const Color(0xFF6B7494),
                    ),
                  ),
                ),
                const SizedBox(height: 48),
                Text(
                  'Welcome back',
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sign in to continue',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: const Color(0xFF4A5070),
                  ),
                ),
                const SizedBox(height: 28),
                _InputField(
                  controller: _nameCtrl,
                  label: 'Full name',
                  hint: 'Your name',
                  icon: Icons.person_outline_rounded,
                ),
                const SizedBox(height: 14),
                _InputField(
                  controller: _emailCtrl,
                  label: 'Email address',
                  hint: 'you@example.com',
                  icon: Icons.mail_outline_rounded,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 14),
                _InputField(
                  controller: _passCtrl,
                  label: 'Password',
                  hint: '••••••••',
                  icon: Icons.lock_outline_rounded,
                  obscureText: _obscurePass,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePass
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: const Color(0xFF4A5070),
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePass = !_obscurePass),
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Forgot password?',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFF00E5CC),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00E5CC), Color(0xFF0A84FF)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.black,
                        ),
                      )
                          : Text(
                        'Sign In',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(
                        child: Divider(color: Color(0xFF1E1E35), height: 1)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text(
                        'or continue with',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFF3A3A55),
                        ),
                      ),
                    ),
                    const Expanded(
                        child: Divider(color: Color(0xFF1E1E35), height: 1)),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _googleLogin,
                    icon: const Icon(Icons.g_mobiledata_rounded,
                        color: Colors.white, size: 26),
                    label: Text(
                      'Continue with Google',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF1E1E35)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      backgroundColor: const Color(0xFF12121F),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Center(
                  child: RichText(
                    text: TextSpan(
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF3A3A55),
                      ),
                      children: const [
                        TextSpan(text: "Don't have an account? "),
                        TextSpan(
                          text: 'Sign Up',
                          style: TextStyle(
                            color: Color(0xFF00E5CC),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Input Field Widget ───────────────────────────────────────────────────────

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextInputType keyboardType;

  const _InputField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.suffixIcon,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF6B7494),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          style: GoogleFonts.inter(fontSize: 14, color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(
              fontSize: 14,
              color: const Color(0xFF2A2A45),
            ),
            prefixIcon: Icon(icon, color: const Color(0xFF4A5070), size: 20),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: const Color(0xFF12121F),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF1E1E35)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
              const BorderSide(color: Color(0xFF00E5CC), width: 1.5),
            ),
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }
}

// ─── Intro / Onboarding Screen ────────────────────────────────────────────────

class IntroScreen extends StatefulWidget {
  final UserModel user;
  const IntroScreen({super.key, required this.user});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..forward();
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: FadeTransition(
        opacity: _fade,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    color: const Color(0xFF00E5CC).withValues(alpha: 0.08),
                    border: Border.all(
                      color: const Color(0xFF00E5CC).withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(Icons.shield_outlined,
                      color: Color(0xFF00E5CC), size: 40),
                ),
                const SizedBox(height: 20),
                Text(
                  'GuardianDrive',
                  style: GoogleFonts.inter(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'AI-powered road safety — for everyone.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: const Color(0xFF6B7494),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF12121F),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFF1E1E35)),
                  ),
                  child: Text(
                    'GuardianDrive combines real-time AI monitoring, peer-to-peer hazard sharing, and emergency response tools into a single platform — keeping drivers, fleets, and first responders connected and safe on every road.',
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      height: 1.65,
                      color: const Color(0xFF8A90AA),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 28),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'FEATURES',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF3A3A55),
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                ...kAllFeatures.map((f) => _IntroFeatureTile(feature: f)),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00E5CC), Color(0xFF0A84FF)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          PageRouteBuilder(
                            pageBuilder: (_, anim, __) =>
                                HomeScreen(user: widget.user),
                            transitionsBuilder: (_, anim, __, child) =>
                                FadeTransition(opacity: anim, child: child),
                            transitionDuration:
                            const Duration(milliseconds: 400),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        'Get Started →',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IntroFeatureTile extends StatelessWidget {
  final FeatureData feature;
  const _IntroFeatureTile({required this.feature});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF12121F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E1E35)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: feature.iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: feature.iconColor.withValues(alpha: 0.25)),
            ),
            child: Icon(feature.icon, color: feature.iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${feature.title} ${feature.subtitle}',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFE8EAF6),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  feature.description,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: const Color(0xFF4A5070),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (feature.isLive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF00E5CC).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: const Color(0xFF00E5CC).withValues(alpha: 0.3)),
              ),
              child: Text(
                'LIVE',
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF00E5CC),
                  letterSpacing: 0.8,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Home Screen ──────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  final UserModel user;
  const HomeScreen({super.key, required this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late final BluetoothChatService _chatService;
  late AnimationController _pulseController;
  late AnimationController _slideController;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _navIndex = 0;

  @override
  void initState() {
    super.initState();
    _chatService = BluetoothChatService();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
  }

  @override
  void dispose() {
    _chatService.dispose();
    _pulseController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  void _onNavTap(int index) {
    if (index == _navIndex) return;
    setState(() {
      _navIndex = index;
      _slideController.forward(from: 0);
    });
  }

  Widget _buildCurrentScreen() {
    switch (_navIndex) {
      case 0:  return const CognitiveLoadScreen();
      case 1:  return const HazardScreen();
      case 2:  return const NearMissScreen();
      case 3:  return const CrashTriageScreen();
      case 4:  return const ChatbotScreen();
      case 5:  return const PotholeScreen();
      default: return const CognitiveLoadScreen();
    }
  }

  void _signOut() {
    Navigator.pop(context);
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, anim, __) => const LoginScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  Color get _accent {
    switch (_navIndex) {
      case 0:  return const Color(0xFF00E5CC);
      case 1:  return const Color(0xFFBF5AF2);
      case 2:  return const Color(0xFFFF9F0A);
      case 3:  return const Color(0xFFFF3B30);
      case 4:  return const Color(0xFF30D158);
      case 5:  return const Color(0xFFFF3B30);
      default: return const Color(0xFF00E5CC);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF0A0A0F),
      drawer: _ProfileDrawer(
        user: widget.user,
        onSignOut: _signOut,
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: KeyedSubtree(
          key: ValueKey(_navIndex),
          child: _buildCurrentScreen(),
        ),
      ),
      bottomNavigationBar: _BottomNav(
        currentIndex: _navIndex,
        accent: _accent,
        onTap: _onNavTap,
        onProfileTap: () => _scaffoldKey.currentState?.openDrawer(),
      ),
    );
  }
}

// ─── Bottom Navigation Bar ────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final Color accent;
  final ValueChanged<int> onTap;
  final VoidCallback onProfileTap;

  const _BottomNav({
    required this.currentIndex,
    required this.accent,
    required this.onTap,
    required this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A0F),
        border: Border(
          top: BorderSide(color: Color(0xFF1E1E35), width: 0.5),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.psychology_outlined,
                label: 'Cognitive',
                isActive: currentIndex == 0,
                color: const Color(0xFF00E5CC),
                onTap: () => onTap(0),
              ),
              _NavItem(
                icon: Icons.hub_outlined,
                label: 'Mesh',
                isActive: currentIndex == 1,
                color: const Color(0xFFBF5AF2),
                onTap: () => onTap(1),
              ),
              _NavItem(
                icon: Icons.route_outlined,
                label: 'Near-Miss',
                isActive: currentIndex == 2,
                color: const Color(0xFFFF9F0A),
                onTap: () => onTap(2),
              ),
              _NavItem(
                icon: Icons.emergency_outlined,
                label: 'Triage',
                isActive: currentIndex == 3,
                color: const Color(0xFFFF3B30),
                onTap: () => onTap(3),
              ),
              _NavItem(
                icon: Icons.smart_toy_outlined,
                label: 'AI Chat',
                isActive: currentIndex == 4,
                color: const Color(0xFF30D158),
                onTap: () => onTap(4),
              ),
              _NavItem(
                icon: Icons.warning_amber_rounded,
                label: 'Pothole',
                isActive: currentIndex == 5,
                color: const Color(0xFFFF3B30),
                onTap: () => onTap(5),
              ),
              // Profile opens drawer — never "active" as a tab
              _NavItem(
                icon: Icons.person_outline,
                label: 'Profile',
                isActive: false,
                color: const Color(0xFF0A84FF),
                onTap: onProfileTap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color color;
  final VoidCallback? onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    this.isActive = false,
    this.color = const Color(0xFF2A2A45),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(6),
              decoration: isActive
                  ? BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              )
                  : null,
              child: Icon(
                icon,
                color: isActive ? color : const Color(0xFF2A2A45),
                size: 20,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 9,
                color: isActive ? color : const Color(0xFF2A2A45),
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Profile Drawer ───────────────────────────────────────────────────────────

class _ProfileDrawer extends StatelessWidget {
  final UserModel user;
  final VoidCallback onSignOut;

  const _ProfileDrawer({
    required this.user,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF0A0A0F),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Profile',
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.4,
                    ),
                  ),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () {},
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E5CC)
                                .withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFF00E5CC)
                                  .withValues(alpha: 0.25),
                            ),
                          ),
                          child: Text(
                            'Edit',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF00E5CC),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(Icons.close,
                            color: Color(0xFF4A5070), size: 22),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // Avatar
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00E5CC), Color(0xFF0A84FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: const Color(0xFF00E5CC).withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    user.initials,
                    style: GoogleFonts.inter(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                user.displayName,
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                user.email,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: const Color(0xFF4A5070),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5CC).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF00E5CC).withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  'Driver',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF00E5CC),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Stats
              Row(
                children: const [
                  _ProfileStat(value: '94%', label: 'Safety Score'),
                  SizedBox(width: 8),
                  _ProfileStat(value: '0', label: 'Incidents'),
                  SizedBox(width: 8),
                  _ProfileStat(value: '128', label: 'Trips'),
                ],
              ),
              const SizedBox(height: 22),

              _DrawerSectionLabel('ACCOUNT'),
              const SizedBox(height: 10),
              _DrawerTile(
                icon: Icons.person_outline,
                iconColor: const Color(0xFF00E5CC),
                label: 'Edit Profile',
                onTap: () {},
              ),
              _DrawerTile(
                icon: Icons.notifications_outlined,
                iconColor: const Color(0xFF0A84FF),
                label: 'Notifications',
                onTap: () {},
              ),
              _DrawerTile(
                icon: Icons.privacy_tip_outlined,
                iconColor: const Color(0xFFBF5AF2),
                label: 'Privacy & Data',
                onTap: () {},
              ),
              const SizedBox(height: 16),

              _DrawerSectionLabel('SUPPORT'),
              const SizedBox(height: 10),
              _DrawerTile(
                icon: Icons.help_outline_rounded,
                iconColor: const Color(0xFFFF9F0A),
                label: 'Help Center',
                onTap: () {},
              ),
              _DrawerTile(
                icon: Icons.star_outline_rounded,
                iconColor: const Color(0xFF30D158),
                label: 'Rate GuardianDrive',
                onTap: () {},
              ),
              _DrawerTile(
                icon: Icons.info_outline_rounded,
                iconColor: const Color(0xFF6B7494),
                label: 'About',
                onTap: () {},
                trailing: Text(
                  'v1.0.0',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: const Color(0xFF3A3A55),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: onSignOut,
                  icon: const Icon(Icons.logout_rounded,
                      color: Color(0xFFFF3B30), size: 18),
                  label: Text(
                    'Sign Out',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFFF3B30),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                        color: Color(0xFFFF3B30), width: 1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    backgroundColor:
                    const Color(0xFFFF3B30).withValues(alpha: 0.06),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Drawer helpers ───────────────────────────────────────────────────────────

class _DrawerSectionLabel extends StatelessWidget {
  final String text;
  const _DrawerSectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF3A3A55),
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  const _DrawerTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF12121F),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: const Color(0xFF1E1E35)),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: iconColor.withValues(alpha: 0.2)),
              ),
              child: Icon(icon, color: iconColor, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFFE8EAF6),
                ),
              ),
            ),
            trailing ??
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF2A2A45),
                  size: 18,
                ),
          ],
        ),
      ),
    );
  }
}

// ─── Profile Stat widget ──────────────────────────────────────────────────────

class _ProfileStat extends StatelessWidget {
  final String value;
  final String label;
  const _ProfileStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF12121F),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1E1E35)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 9,
                color: const Color(0xFF3A3A55),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}