import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/login_screen.dart';
import '../../services/notification_service.dart';
import '../tickets/tickets_list_screen.dart';
import 'tabs/marketplace_tab.dart';
import 'tabs/categories_tab.dart';
import 'tabs/cart_tab.dart';
import 'tabs/profile_tab.dart';

const _kPrimary = Color(0xFF0D9488);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  static _HomeScreenState? _state;
  static void showTab(int index) {
    _state?.setTab(index);
  }

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  bool _initializing = true;
  final List<Widget> _screens = [];
  final GlobalKey<MarketplaceTabState> _marketplaceTabKey =
      GlobalKey<MarketplaceTabState>();
  final GlobalKey<CartTabState> _cartTabKey = GlobalKey<CartTabState>();

  @override
  void initState() {
    super.initState();
    HomeScreen._state = this;
    _screens.addAll([
      MarketplaceTab(
        key: _marketplaceTabKey,
        onInitialLoadComplete: _finishInitialLoad,
      ),
      const CategoriesTab(),
      CartTab(key: _cartTabKey),
      const TicketsListScreen(),
      ProfileTab(onSignOut: _signOut),
    ]);
    _subscribeToNotifications();
  }

  void _finishInitialLoad() {
    if (!mounted || !_initializing) return;
    setState(() => _initializing = false);
  }

  @override
  void dispose() {
    if (HomeScreen._state == this) {
      HomeScreen._state = null;
    }
    _unsubscribeFromNotifications();
    super.dispose();
  }

  void _unsubscribeFromNotifications() {
    NotificationService.instance.stopListening();
  }

  void _subscribeToNotifications() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    NotificationService.instance.startListening(userId);
  }

  Future<void> _signOut() async {
    try {
      _unsubscribeFromNotifications();
      await Supabase.instance.client.auth.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void setTab(int index) {
    setState(() => _currentIndex = index);
    if (index == 2) {
      _cartTabKey.currentState?.load();
    } else if (index == 0) {
      _marketplaceTabKey.currentState?.load(isLiveSearch: true);
    }
  }

  void showSupport() {
    setTab(3);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: List.generate(
              _screens.length,
              (index) => TickerMode(
                enabled: _currentIndex == index,
                child: _screens[index],
              ),
            ),
          ),
          if (_initializing)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.white,
                child: Center(
                  child: CircularProgressIndicator(color: _kPrimary),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _initializing
          ? null
          : Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Theme(
                data: Theme.of(context).copyWith(
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  focusColor: Colors.transparent,
                ),
                child: BottomNavigationBar(
                  currentIndex: _currentIndex,
                  onTap: (i) {
                    setState(() => _currentIndex = i);
                    if (i == 0) {
                      _marketplaceTabKey.currentState?.load(isLiveSearch: true);
                    } else if (i == 2) {
                      _cartTabKey.currentState?.load();
                    }
                  },
                  type: BottomNavigationBarType.fixed,
                  selectedItemColor: _kPrimary,
                  unselectedItemColor: Colors.grey.shade500,
                  selectedFontSize: 11,
                  unselectedFontSize: 10,
                  backgroundColor: Colors.white,
                  elevation: 0,
                  items: const [
                    BottomNavigationBarItem(
                      icon: Icon(Icons.home_outlined),
                      activeIcon: Icon(Icons.home),
                      label: 'Inicio',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.grid_view_outlined),
                      activeIcon: Icon(Icons.grid_view),
                      label: 'Categorías',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.shopping_cart_outlined),
                      activeIcon: Icon(Icons.shopping_cart),
                      label: 'Carrito',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.support_agent_outlined),
                      activeIcon: Icon(Icons.support_agent),
                      label: 'Soporte',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.person_outline),
                      activeIcon: Icon(Icons.person),
                      label: 'Perfil',
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
