// ignore_for_file: non_constant_identifier_names
// ignore_for_file: library_private_types_in_public_api
//
// Dart bindings for the C bridge shim (app/native/bridge.{h,c}, FP-22b).
// These structs MUST match bridge.h field-for-field. The shim hands Dart
// heap-owned copies that survive past the core's synchronous callback; Dart
// frees them with rt_free_* after reading.

import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

/// Flat, owned mirror of TogglTimeEntryView — matches `RtTimeEntry` in bridge.h.
final class RtTimeEntry extends ffi.Struct {
  @ffi.Uint64()
  external int ID;
  @ffi.Int64()
  external int DurationInSeconds;
  external ffi.Pointer<Utf8> Description;
  external ffi.Pointer<Utf8> Duration;
  external ffi.Pointer<Utf8> ProjectLabel;
  external ffi.Pointer<Utf8> TaskLabel;
  external ffi.Pointer<Utf8> ClientLabel;
  external ffi.Pointer<Utf8> Color;
  external ffi.Pointer<Utf8> GUID;
  external ffi.Pointer<Utf8> Tags;
  @ffi.Int()
  external int Billable;
  @ffi.Uint64()
  external int ActivityID;
  @ffi.Uint64()
  external int Started;
  @ffi.Uint64()
  external int Ended;
  external ffi.Pointer<Utf8> StartTimeString;
  external ffi.Pointer<Utf8> EndTimeString;
  @ffi.Int()
  external int IsHeader;
  external ffi.Pointer<Utf8> DateHeader;
  external ffi.Pointer<Utf8> DateDuration;
  @ffi.Int()
  external int Unsynced;
  external ffi.Pointer<Utf8> Error;
}

/// Matches `RtTimeEntryList` in bridge.h.
final class RtTimeEntryList extends ffi.Struct {
  @ffi.Int64()
  external int count;
  @ffi.Int()
  external int show_load_more;
  external ffi.Pointer<RtTimeEntry> items;
}

typedef RtTimeEntryListCbNative = ffi.Void Function(
    ffi.Pointer<RtTimeEntryList> owned);
typedef RtTimerStateCbNative = ffi.Void Function(
    ffi.Pointer<RtTimeEntry> ownedOrNull);

typedef _RtOnListNative = ffi.Void Function(ffi.Pointer<ffi.Void> ctx,
    ffi.Pointer<ffi.NativeFunction<RtTimeEntryListCbNative>> cb);
typedef _RtOnListDart = void Function(ffi.Pointer<ffi.Void> ctx,
    ffi.Pointer<ffi.NativeFunction<RtTimeEntryListCbNative>> cb);

typedef _RtOnTimerNative = ffi.Void Function(ffi.Pointer<ffi.Void> ctx,
    ffi.Pointer<ffi.NativeFunction<RtTimerStateCbNative>> cb);
typedef _RtOnTimerDart = void Function(ffi.Pointer<ffi.Void> ctx,
    ffi.Pointer<ffi.NativeFunction<RtTimerStateCbNative>> cb);

typedef _RtFreeListNative = ffi.Void Function(ffi.Pointer<RtTimeEntryList>);
typedef _RtFreeListDart = void Function(ffi.Pointer<RtTimeEntryList>);

typedef _RtFreeOneNative = ffi.Void Function(ffi.Pointer<RtTimeEntry>);
typedef _RtFreeOneDart = void Function(ffi.Pointer<RtTimeEntry>);

/// Typed wrapper over the `rt_*` bridge symbols.
class RtBridge {
  RtBridge(ffi.DynamicLibrary lib)
      : onTimeEntryList = lib
            .lookupFunction<_RtOnListNative, _RtOnListDart>(
                'rt_on_time_entry_list'),
        onTimerState = lib.lookupFunction<_RtOnTimerNative, _RtOnTimerDart>(
            'rt_on_timer_state'),
        freeList = lib.lookupFunction<_RtFreeListNative, _RtFreeListDart>(
            'rt_free_time_entry_list'),
        freeOne = lib.lookupFunction<_RtFreeOneNative, _RtFreeOneDart>(
            'rt_free_time_entry');

  final _RtOnListDart onTimeEntryList;
  final _RtOnTimerDart onTimerState;
  final _RtFreeListDart freeList;
  final _RtFreeOneDart freeOne;
}
