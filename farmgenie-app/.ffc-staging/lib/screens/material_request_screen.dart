import 'erp_web_view_screen.dart';

/// ERP material request (indent) page.
class MaterialRequestScreen extends ErpWebViewScreen {
  const MaterialRequestScreen({super.key})
    : super(
        path: '/indent-cy',
        loadFailedMessage: 'Material request page could not be loaded.',
        openFailedMessage: 'Could not open Material Request. Please retry.',
      );
}
