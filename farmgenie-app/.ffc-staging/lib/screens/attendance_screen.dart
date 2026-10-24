import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../services/farmgenie_api.dart';
import '../utils/face/face_auth_flow.dart';
import '../utils/api/face_auth_api.dart';
import '../services/attendance_geofence.dart';
import '../widgets/checkin_design.dart';
import '../widgets/glass_home.dart';
import '../widgets/geofence_warning_dialog.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key, this.recordsOnly = false});

  final bool recordsOnly;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  static const _officeTypes = [
    'Head Office - Alapakkam',
    'Head Office - RWD GrandCorridor',
    'Head Office - Vanagaram',
    'Head Office - Prestige',
  ];
  static const _configuredOfficeTypes = {
    'Head Office - Alapakkam',
    'Head Office - RWD GrandCorridor',
    'Head Office - Vanagaram',
    'Head Office - Prestige',
  };

  String _employeeName = 'Employee';
  String? _company;
  bool _loading = true;
  bool _actionLoading = false;
  bool _isOperation = false;
  bool _checkedIn = false;
  bool _workCompleted = false;
  String? _checkInTime;
  String? _checkOutTime;
  String? _error;
  String? _officeType;
  Position? _lastPosition;
  String? _locationAddress;
  bool _locationLoading = false;
  bool _calendarLoading = true;
  DateTime _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selectedDate = DateTime.now();
  Map<String, Map<String, dynamic>> _calendarRecords = {};

  @override
  void initState() {
    super.initState();
    if (widget.recordsOnly) {
      _loadCalendar();
    } else {
      _loadStatus();
      _refreshLocation();
    }
  }

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<void> _loadCalendar() async {
    if (mounted) setState(() => _calendarLoading = true);
    try {
      final records = await FarmgenieApi.attendanceCalendar(_calendarMonth);
      if (!mounted) return;
      setState(() {
        _calendarRecords = {
          for (final record in records)
            if (record['date'] != null) record['date'].toString(): record,
        };
      });
    } on FarmgenieApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Could not load attendance records.');
    } finally {
      if (mounted) setState(() => _calendarLoading = false);
    }
  }

  Future<void> _changeMonth(int offset) async {
    setState(() {
      _calendarMonth = DateTime(
        _calendarMonth.year,
        _calendarMonth.month + offset,
      );
      _selectedDate = DateTime(_calendarMonth.year, _calendarMonth.month, 1);
    });
    await _loadCalendar();
  }

  Future<void> _refreshLocation() async {
    if (!mounted) return;
    setState(() {
      _locationLoading = true;
      _lastPosition = null;
      _error = null;
    });
    try {
      final position = await _position();
      // Reverse geocoding is optional; valid GPS must remain usable if it fails.
      var placemarks = <Placemark>[];
      try {
        placemarks = await Geocoding()
            .placemarkFromCoordinates(position.latitude, position.longitude)
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
      final place = placemarks.isNotEmpty ? placemarks.first : null;
      final parts =
          [
                place?.street,
                place?.subLocality,
                place?.locality,
                place?.administrativeArea,
                place?.postalCode,
                place?.country,
              ]
              .whereType<String>()
              .map((part) => part.trim())
              .where((part) => part.isNotEmpty)
              .toSet()
              .toList();
      if (!mounted) return;
      setState(() {
        _lastPosition = position;
        _locationAddress = parts.isEmpty
            ? 'Current location detected'
            : parts.join(', ');
      });
    } on FarmgenieApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not read your current location.');
      }
    } finally {
      if (mounted) setState(() => _locationLoading = false);
    }
  }

  Future<void> _loadStatus() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await FarmgenieApi.attendanceStatus();
      _applyStatus(response['data']);
    } on FarmgenieApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load attendance status.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyStatus(dynamic raw) {
    if (raw is! Map) return;
    if (!mounted) return;
    setState(() {
      _employeeName = raw['employee_name']?.toString() ?? _employeeName;
      _company = raw['company']?.toString() ?? _company;
      _isOperation =
          raw['is_operation'] == true ||
          raw['is_operation'] == 1 ||
          raw['is_operation'] == '1';
      final office = raw['office_type']?.toString();
      _officeType = office == null
          ? null
          : AttendanceGeofence.canonicalOffice(office);
      _checkedIn = raw['checked_in'] == true;
      _checkInTime = raw['check_in_time']?.toString();
      _checkOutTime = raw['check_out_time']?.toString();
      _workCompleted = raw['work_completed'] is bool
          ? raw['work_completed'] == true
          : (_checkInTime != null &&
                _checkInTime!.isNotEmpty &&
                _checkOutTime != null &&
                _checkOutTime!.isNotEmpty);
    });
  }

  Future<Position> _position() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const FarmgenieApiException(
        'Turn on location services to continue.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const FarmgenieApiException('Location permission is required.');
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
  }

  void _validateGeofence(String office, Position position) {
    if (!AttendanceGeofence.validCoordinates(
      position.latitude,
      position.longitude,
    )) {
      throw const FarmgenieApiException(
        'Could not read valid GPS coordinates. Refresh location.',
      );
    }
    if (_isOperation) return;
    final distance = AttendanceGeofence.distanceMeters(
      office,
      position.latitude,
      position.longitude,
    );
    if (distance == null) {
      throw const FarmgenieApiException(
        'Your office location is missing or not configured. Contact HR.',
      );
    }
    if (distance > AttendanceGeofence.radiusMeters) {
      throw FarmgenieApiException(
        'You are ${distance.round()} meters from $office. Move within ${AttendanceGeofence.radiusMeters.round()} meters to check ${_checkedIn ? 'out' : 'in'}.',
      );
    }
  }

  Future<void> _showLocationWarning(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => GeofenceWarningDialog(message: message),
    );
  }

  Future<void> _attendanceAction() async {
    if (_actionLoading || _loading) return;
    setState(() {
      _actionLoading = true;
      _error = null;
    });
    try {
      // Refresh authenticated attendance and exemption before making a decision.
      final status = await FarmgenieApi.attendanceStatus();
      if (!mounted) return;
      if (status['data'] is! Map) {
        throw const FarmgenieApiException(
          'Could not verify attendance status. Please refresh.',
        );
      }
      _applyStatus(status['data']);
      if (_workCompleted && !_checkedIn) {
        throw const FarmgenieApiException(
          'Work completed for today. You cannot check in again today.',
        );
      }
      final selectedOffice = _checkedIn
          ? (_officeType ?? '')
          : _isOperation
          ? 'Operation'
          : await _selectOfficeType();
      if (selectedOffice == null || !mounted) return;
      setState(() => _officeType = selectedOffice);
      final confirmed = await _confirmAttendance(
        selectedOffice.isEmpty ? 'Your check-in location' : selectedOffice,
      );
      if (!confirmed || !mounted) return;
      // Complete the reference app's blink and face match before checking the
      // geofence. Fresh GPS must pass before a receipt or attendance is sent.
      final verified = await FaceAuthFlow.instance.verify(
        context: context,
        action: _checkedIn ? 'attendance_out' : 'attendance_in',
        overlapLocationWithMatching: false,
        refreshLocation: () async {
          await _refreshLocation();
          if (!mounted || _lastPosition == null) {
            throw FarmgenieApiException(
              _error ?? 'Could not read your current location.',
            );
          }
          _validateGeofence(selectedOffice, _lastPosition!);
          return (
            position: _lastPosition!,
            address: _locationAddress ?? 'Current location detected',
          );
        },
      );
      if (verified == null || !mounted) return;
      await FaceAuthApi.instance.assertSessionUser(verified.currentUser);
      final position = verified.position;
      final response = await FarmgenieApi.attendanceAction(
        action: _checkedIn ? 'check_out' : 'check_in',
        latitude: position.latitude,
        longitude: position.longitude,
        officeType: selectedOffice,
        address: verified.address,
        faceVerification: verified.recordId,
        faceCsrfToken: verified.receipt.csrfToken,
        expectedLastCheckin:
            (status['data'] as Map)['latest_checkin_id'] as String,
      );
      _applyStatus(response['data']);
      if (mounted) await _showSuccess();
    } on FarmgenieApiException catch (error) {
      if (GeofenceWarningDialog.matchesMessage(error.message)) {
        if (mounted) setState(() => _error = null);
        await _showLocationWarning(error.message);
      } else {
        if (mounted) setState(() => _error = error.message);
      }
    } on StateError catch (error) {
      if (mounted) {
        setState(() => _error = error.message.toString());
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Face verification required'),
            content: Text(error.message.toString()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Attendance request failed.');
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<String?> _selectOfficeType() async {
    String? selected = _officeType;
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xF0EEFFF6),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Select Office Location',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close, size: 20),
                      ),
                    ],
                  ),
                  const Text(
                    'Choose your check-in location to continue.',
                    style: TextStyle(color: Color(0xFF526078), height: 1.5),
                  ),
                  const SizedBox(height: 18),
                  ..._officeTypes.map(
                    (office) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Material(
                        color: selected == office
                            ? const Color(0xFFEAF9F1)
                            : const Color(0xFFF5F7FB),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: selected == office
                                ? brandGreen
                                : Colors.transparent,
                          ),
                        ),
                        child: ListTile(
                          onTap: _configuredOfficeTypes.contains(office)
                              ? () => update(() => selected = office)
                              : null,
                          leading: Icon(
                            selected == office
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            color: selected == office
                                ? brandGreen
                                : const Color(0xFF738099),
                          ),
                          title: Text(
                            office,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            _configuredOfficeTypes.contains(office)
                                ? 'Office location'
                                : 'Not configured',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF738099),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ActionButton(
                          label: _checkedIn ? 'Check Out' : 'Check In',
                          checkout: _checkedIn,
                          onPressed: selected == null
                              ? null
                              : () => Navigator.pop(sheetContext, selected),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmAttendance(String office) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => Dialog(
            backgroundColor: const Color(0xF0EEFFF6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      onPressed: () => Navigator.pop(context, false),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ),
                  CircleAvatar(
                    radius: 29,
                    backgroundColor: _checkedIn ? brandOrange : brandGreen,
                    child: Icon(
                      _checkedIn ? Icons.logout_rounded : Icons.login_rounded,
                      color: Colors.white,
                      size: 29,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _checkedIn ? 'Confirm Check Out' : 'Confirm Check In',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Are you sure you want to ${_checkedIn ? 'check out' : 'check in'}?\n$office',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF526078),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                      ),
                      Expanded(
                        child: ActionButton(
                          label: _checkedIn ? 'Yes, Check Out' : 'Check In',
                          checkout: _checkedIn,
                          onPressed: () => Navigator.pop(context, true),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ) ??
        false;
  }

  Future<void> _showSuccess() => showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: const Color(0xF0EEFFF6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, size: 18),
              ),
            ),
            const CircleAvatar(
              radius: 29,
              backgroundColor: brandGreen,
              child: Icon(Icons.check_rounded, color: Colors.white, size: 34),
            ),
            const SizedBox(height: 18),
            Text(
              _checkedIn
                  ? 'Checked In Successfully!'
                  : 'Checked Out Successfully!',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              'You have checked ${_checkedIn ? 'in' : 'out'} at\n${_officeType ?? 'your office'}\nat ${_clock(_checkedIn ? _checkInTime : _checkOutTime)}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF526078), height: 1.5),
            ),
            const SizedBox(height: 22),
            ActionButton(label: 'OK', onPressed: () => Navigator.pop(context)),
          ],
        ),
      ),
    ),
  );

  String _yesNo(dynamic value) {
    return value == true || value == 1 || value?.toString() == '1'
        ? 'Yes'
        : 'No';
  }

  String? _calendarStatus(Map<String, dynamic>? record) {
    final status = record?['status']?.toString().toLowerCase();
    if (status == 'leave') return 'leave';
    if (record == null) return null;
    if (status == 'absent') return 'absent';
    if (status == 'present') return 'present';
    if (status == 'half' || record['half_day'] == true) return 'half';
    if (record['check_in_time'] != null && record['check_out_time'] != null) {
      return 'present';
    }
    return 'half';
  }

  Widget _calendarLegendItem({required Color color, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 10,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .20),
            border: Border.all(color: color, width: 1.2),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  Widget _attendanceCalendar() {
    final daysInMonth = DateTime(
      _calendarMonth.year,
      _calendarMonth.month + 1,
      0,
    ).day;
    final leadingDays =
        DateTime(_calendarMonth.year, _calendarMonth.month, 1).weekday - 1;
    final monthName = _monthNames[_calendarMonth.month - 1];

    return FarmgenieGlassCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Attendance records',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _changeMonth(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(
                  '$monthName ${_calendarMonth.year}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _changeMonth(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Text('M'),
                Text('T'),
                Text('W'),
                Text('T'),
                Text('F'),
                Text('S'),
                Text('S'),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 6,
              children: [
                _calendarLegendItem(color: Color(0xFF2D9B57), label: 'Present'),
                _calendarLegendItem(color: Color(0xFFE53935), label: 'Absent'),
                _calendarLegendItem(color: Color(0xFF2F80ED), label: 'Leave'),
                _calendarLegendItem(
                  color: Color(0xFFF2C94C),
                  label: 'Half day',
                ),
              ],
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: leadingDays + daysInMonth,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
              itemBuilder: (context, index) {
                if (index < leadingDays) return const SizedBox.shrink();
                final day = index - leadingDays + 1;
                final date = DateTime(
                  _calendarMonth.year,
                  _calendarMonth.month,
                  day,
                );
                final record = _calendarRecords[_dateKey(date)];
                final selected = _dateKey(date) == _dateKey(_selectedDate);
                final status = _calendarStatus(record);
                final statusColor = status == 'leave'
                    ? const Color(0xFF2F80ED)
                    : status == 'half'
                    ? const Color(0xFFF2C94C)
                    : status == 'present'
                    ? const Color(0xFF2D9B57)
                    : status == 'absent'
                    ? const Color(0xFFE53935)
                    : status == null && !date.isAfter(DateTime.now())
                    ? const Color(0xFFE53935)
                    : null;
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _selectedDate = date),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      color: statusColor == null
                          ? (selected
                                ? const Color(0xFFC5F5DE)
                                : const Color(0x99FFFFFF))
                          : statusColor.withValues(alpha: selected ? .32 : .14),
                      border: statusColor == null
                          ? (selected
                                ? Border.all(
                                    color: const Color(0xFF2D6A3F)
                                        .withValues(alpha: .55),
                                    width: 1.3,
                                  )
                                : null)
                          : Border.all(
                              color: statusColor.withValues(
                                alpha: selected ? .90 : .65,
                              ),
                              width: selected ? 1.8 : 1.3,
                            ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Text(
                          '$day',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            if (_calendarLoading)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
        ),
      ),
    );
  }

  Widget _selectedDayDetails() {
    final record = _calendarRecords[_dateKey(_selectedDate)];
    return FarmgenieGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: record == null
              ? Row(
                  key: const ValueKey('empty-day'),
                  children: [
                    const Icon(
                      Icons.event_available_outlined,
                      color: Color(0xFF2D6A3F),
                    ),
                    const SizedBox(width: 12),
                    Text('No record for ${_dateKey(_selectedDate)}.'),
                  ],
                )
              : Column(
                  key: ValueKey(_dateKey(_selectedDate)),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record['attendance_date']?.toString() ??
                          _dateKey(_selectedDate),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _detail('Late entry', _yesNo(record['late_entry'])),
                    _detail('Early exit', _yesNo(record['early_exit'])),
                  ],
                ),
        ),
      ),
    );
  }

  static const _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  String _time(String? value) => value == null || value.isEmpty ? '—' : value;

  String _clock(String? value) {
    final time = DateTime.tryParse(value ?? '');
    if (time == null) return '--:--';
    return '${time.hour % 12 == 0 ? 12 : time.hour % 12}:${time.minute.toString().padLeft(2, '0')} ${time.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        if (_actionLoading) return;
        if (widget.recordsOnly) {
          await _loadCalendar();
        } else {
          await Future.wait([_loadStatus(), _refreshLocation()]);
        }
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (widget.recordsOnly) ...[
            const Text(
              'Attendance Records',
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text('Select a date to view your attendance.'),
            const SizedBox(height: 18),
            _attendanceCalendar(),
            const SizedBox(height: 12),
            _selectedDayDetails(),
          ] else ...[
            FarmgenieHomeEntrance(
              child: FarmgenieGreetingCard(
                name: _employeeName,
                checkedIn: _checkedIn,
              ),
            ),
            const SizedBox(height: 10),
            FarmgenieAttendanceStatusCard(
              loading: _loading,
              completed: _workCompleted,
              checkedIn: _checkedIn,
              title: _loading
                  ? 'Loading status...'
                  : _workCompleted
                  ? 'Work Completed'
                  : _checkedIn
                  ? 'You are Checked In'
                  : 'Not Checked In',
              description: _workCompleted
                  ? 'Your check-in and check-out are complete for today.'
                  : _checkedIn
                  ? _officeType == null
                        ? 'Have a productive day!'
                        : 'Office: $_officeType'
                  : 'Check in to start your workday and begin today\'s work.',
              checkInTime: _clock(_checkInTime),
              checkOutTime: _clock(_checkOutTime),
            ),
            const SizedBox(height: 9),
            FarmgenieAttendanceActionButton(
              label: _workCompleted
                  ? 'Work Completed'
                  : _checkedIn
                  ? 'Check Out'
                  : 'Check In',
              completed: _workCompleted,
              checkout: _checkedIn,
              busy: _actionLoading,
              onPressed: _loading || _locationLoading || _workCompleted
                  ? null
                  : _attendanceAction,
            ),
            const SizedBox(height: 10),
            FarmgenieLocationCard(
              address: _locationLoading
                  ? 'Finding your current location...'
                  : _locationAddress ?? 'Location unavailable',
              loading: _locationLoading,
              onRefresh: _locationLoading || _actionLoading
                  ? null
                  : _refreshLocation,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
    );
  }

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}
