import 'package:flutter/material.dart';

import '../services/farmgenie_api.dart';
import '../widgets/glass_home.dart';

class LeaveRequestScreen extends StatefulWidget {
  const LeaveRequestScreen({super.key});

  @override
  State<LeaveRequestScreen> createState() => _LeaveRequestScreenState();
}

class _LeaveRequestScreenState extends State<LeaveRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  static const _leaveTypes = ['Compensatory Off', 'Leave Without Pay'];
  String? _leaveType;
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _halfDay = false;
  bool _loadingProfile = true;
  bool _submitting = false;
  String? _employeeId;
  String? _company;
  String? _leaveApprover;
  String? _error;
  String? _leaveTypeError;
  bool _dateError = false;

  @override
  void initState() {
    super.initState();
    _loadEmployeeDetails();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadEmployeeDetails() async {
    setState(() {
      _loadingProfile = true;
      _error = null;
    });
    try {
      final response = await FarmgenieApi.attendanceStatus();
      final data = response['data'];
      if (data is Map) {
        final employee = data['employee_id'] ?? data['employee'];
        if (mounted) {
          setState(() {
            _employeeId = employee?.toString();
            _company = data['company']?.toString();
            _leaveApprover = data['leave_approver']?.toString();
          });
        }
      }
    } on FarmgenieApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load your employee details.');
      }
    } finally {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  Future<void> _pickFromDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      firstDate: today,
      lastDate: DateTime(today.year + 2, 12, 31),
      initialDate: _fromDate ?? today,
    );
    if (!mounted || picked == null) return;
    setState(() {
      _fromDate = picked;
      _dateError = false;
      if (_toDate != null && _toDate!.isBefore(picked)) _toDate = picked;
    });
  }

  Future<void> _pickToDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final firstDate = _fromDate ?? today;
    final picked = await showDatePicker(
      context: context,
      firstDate: firstDate,
      lastDate: DateTime(today.year + 2, 12, 31),
      initialDate: _toDate ?? firstDate,
    );
    if (!mounted || picked == null) return;
    setState(() {
      _toDate = picked;
      _dateError = false;
    });
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  String _displayDate(DateTime? value) {
    if (value == null) return 'Select date';
    return MaterialLocalizations.of(context).formatMediumDate(value);
  }

  Future<void> _submit() async {
    final valid = _formKey.currentState?.validate() == true;
    final missingLeaveType = _leaveType == null || _leaveType!.isEmpty;
    final missingDates = _fromDate == null || _toDate == null;
    if (!valid || missingLeaveType || missingDates) {
      setState(() {
        _leaveTypeError = missingLeaveType ? 'Select a leave type.' : null;
        _dateError = missingDates;
      });
      return;
    }
    if (_employeeId == null || _company == null || _employeeId!.isEmpty) {
      setState(() => _error = 'Employee details are not available yet.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await FarmgenieApi.createLeaveRequest(
        fromDate: _date(_fromDate!),
        toDate: _date(_toDate!),
        halfDay: _halfDay,
        leaveType: _leaveType!,
        description: _descriptionController.text.trim(),
        employee: _employeeId!,
        company: _company ?? '',
        leaveApprover: _leaveApprover ?? '',
      );
      if (!mounted) return;
      _descriptionController.clear();
      setState(() {
        _leaveType = null;
        _fromDate = null;
        _toDate = null;
        _halfDay = false;
        _leaveTypeError = null;
        _dateError = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Leave request submitted successfully.')),
      );
    } on FarmgenieApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not submit leave request.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadEmployeeDetails,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          const Text(
            'Leave Request',
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'Submit your leave request for manager approval.',
            style: TextStyle(color: Color(0xFF526078)),
          ),
          const SizedBox(height: 14),
          _employeeDetailsCard(),
          const SizedBox(height: 10),
          _formCard(
            child: DropdownButtonFormField<String>(
              initialValue: _leaveType,
              isExpanded: true,
              hint: const Text('Select leave type'),
              decoration: _inputDecoration(
                label: 'Leave type',
                prefixIcon: Icons.business_center_outlined,
              ),
              items: _leaveTypes
                  .map(
                    (type) => DropdownMenuItem<String>(
                      value: type,
                      child: Text(type),
                    ),
                  )
                  .toList(),
              onChanged: _submitting
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() {
                          _leaveType = value;
                          _leaveTypeError = null;
                        });
                      }
                    },
            ),
          ),
          if (_leaveTypeError != null)
            Padding(
              padding: const EdgeInsets.only(top: 5, left: 4),
              child: Text(
                _leaveTypeError!,
                style: const TextStyle(color: Colors.red, fontSize: 11),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _dateButton(
                  label: 'From date',
                  value: _displayDate(_fromDate),
                  onPressed: _pickFromDate,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _dateButton(
                  label: 'To date',
                  value: _displayDate(_toDate),
                  onPressed: _pickToDate,
                ),
              ),
            ],
          ),
          if (_dateError)
            const Padding(
              padding: EdgeInsets.only(top: 5, left: 4),
              child: Text(
                'Select both leave dates.',
                style: TextStyle(color: Colors.red, fontSize: 11),
              ),
            ),
          const SizedBox(height: 10),
          _halfDayTile(),
          const SizedBox(height: 10),
          Form(
            key: _formKey,
            child: _formCard(
              child: TextFormField(
                controller: _descriptionController,
                maxLines: 3,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a reason.'
                    : null,
                decoration: _inputDecoration(
                  label: 'Reason',
                  hint: 'Enter reason for leave request...',
                  alignLabelWithHint: true,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: forestGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              onPressed: _loadingProfile || _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_outlined),
              label: Text(_submitting ? 'Submitting...' : 'Submit request'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
    );
  }

  Widget _dateButton({
    required String label,
    required String value,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        backgroundColor: const Color(0xB3FFFFFF),
        side: const BorderSide(color: Colors.white, width: 1.8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(21)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 15,
            backgroundColor: Color(0xFFE3F5E9),
            child: Icon(
              Icons.calendar_month_outlined,
              size: 17,
              color: Color(0xFF2D7C4C),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 10)),
                const SizedBox(height: 3),
                Text(value, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _employeeDetailsCard() {
    return FarmgenieGlassCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 20,
            backgroundColor: Color(0xFFE0F2E5),
            child: Icon(Icons.person, color: Color(0xFF2D6A3F)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _loadingProfile
                ? const LinearProgressIndicator(minHeight: 2)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Employee details',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 5),
                      Text('Employee ID: ${_employeeId ?? 'Unavailable'}'),
                      const SizedBox(height: 3),
                      Text('Company: ${_company ?? 'Unavailable'}'),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _formCard({required Widget child}) {
    return FarmgenieGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: child,
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    String? hint,
    IconData? prefixIcon,
    bool alignLabelWithHint = false,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon == null
          ? null
          : Icon(prefixIcon, color: const Color(0xFF2D7C4C)),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      filled: false,
      alignLabelWithHint: alignLabelWithHint,
      counterText: '',
    );
  }

  Widget _halfDayTile() {
    return FarmgenieGlassCard(
      child: CheckboxListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        value: _halfDay,
        onChanged: _submitting
            ? null
            : (value) => setState(() => _halfDay = value == true),
        title: const Text(
          'Half day',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: const Text('Apply this request as a half-day leave.'),
        secondary: const CircleAvatar(
          backgroundColor: Color(0xFFDDEFD7),
          child: Icon(Icons.event_available, color: Color(0xFF5B9C63)),
        ),
        controlAffinity: ListTileControlAffinity.leading,
      ),
    );
  }
}
