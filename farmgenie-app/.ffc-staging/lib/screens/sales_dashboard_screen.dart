import 'erp_web_view_screen.dart';

/// ERP sales dashboard page.
class SalesDashboardScreen extends ErpWebViewScreen {
  const SalesDashboardScreen({super.key})
    : super(
        path: '/sales-dashboard',
        loadFailedMessage: 'Sales Dashboard could not be loaded.',
        openFailedMessage: 'Sales Dashboard could not be loaded.',
      );
}
