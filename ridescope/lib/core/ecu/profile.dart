import 'dart:convert';

import '../../licensing/tier.dart';
import '../adapter/elm327.dart';
import '../util/hex.dart';

enum EcuProtocol { kwp, uds, obd }

enum Risk { low, medium, high }

enum ProcedureKind { service, date, adaptation, calibration, actuator, bleed }

extension ProcedureKindLabel on ProcedureKind {
  String get label => switch (this) {
        ProcedureKind.service => 'Service',
        ProcedureKind.date => 'Date & time',
        ProcedureKind.adaptation => 'Adaptation',
        ProcedureKind.calibration => 'Calibration',
        ProcedureKind.actuator => 'Actuator test',
        ProcedureKind.bleed => 'Brake bleeding',
      };

  /// Tier needed for this kind of procedure unless the profile overrides it.
  Tier get defaultTier => switch (this) {
        ProcedureKind.service || ProcedureKind.date => Tier.plus,
        _ => Tier.pro,
      };
}

T _enum<T extends Enum>(List<T> values, Object? name, T fallback) =>
    values.firstWhere((v) => v.name == name, orElse: () => fallback);

int? _int(Object? v) => v == null ? null : parseIntFlexible(v);
double _num(Object? v, double d) => v == null ? d : (v as num).toDouble();
List<Map<String, dynamic>> _list(Object? v) =>
    (v as List? ?? const []).cast<Map<String, dynamic>>();

/// How to turn raw response bytes into a displayed value.
class ValueEncoding {
  ValueEncoding({
    this.start = 0,
    this.length = 1,
    this.type = 'u',
    this.littleEndian = false,
    this.scale = 1,
    this.offset = 0,
    this.decimals = 0,
    this.labels = const {},
    this.mask,
  });

  factory ValueEncoding.fromJson(Map<String, dynamic>? j) {
    if (j == null) return ValueEncoding();
    return ValueEncoding(
      start: j['start'] ?? 0,
      length: j['length'] ?? 1,
      type: j['type'] ?? 'u',
      littleEndian: j['littleEndian'] ?? false,
      scale: _num(j['scale'], 1),
      offset: _num(j['offset'], 0),
      decimals: j['decimals'] ?? 0,
      labels: {
        for (final e in (j['labels'] as Map? ?? const {}).entries)
          parseIntFlexible(e.key): e.value as String,
      },
      mask: _int(j['mask']),
    );
  }

  final int start;
  final int length;

  /// `u` unsigned, `s` signed, `ascii`, `hex`, `bcd`, `enum`, `date`.
  final String type;
  final bool littleEndian;
  final double scale;
  final double offset;
  final int decimals;
  final Map<int, String> labels;
  final int? mask;

  Map<String, dynamic> toJson() => {
        'start': start,
        'length': length,
        'type': type,
        if (littleEndian) 'littleEndian': true,
        if (scale != 1) 'scale': scale,
        if (offset != 0) 'offset': offset,
        if (decimals != 0) 'decimals': decimals,
        if (labels.isNotEmpty) 'labels': {for (final e in labels.entries) '${e.key}': e.value},
        if (mask != null) 'mask': '0x${hexWord(mask!)}',
      };

  /// Numeric value, or null for text encodings / short data.
  double? decodeNumber(List<int> data) {
    if (type == 'ascii' || type == 'hex' || type == 'date') return null;
    if (data.length < start + length) return null;
    var raw = readUnsigned(data, start, length, bigEndian: !littleEndian);
    if (mask != null) {
      raw &= mask!;
      var m = mask!;
      while (m != 0 && m & 1 == 0) {
        m >>= 1;
        raw >>= 1;
      }
    }
    if (type == 'bcd') {
      var v = 0;
      for (var i = 0; i < length; i++) {
        v = v * 100 + bcdDecode(data[start + i]);
      }
      raw = v;
    }
    if (type == 's') {
      final bits = 8 * length;
      if (raw & (1 << (bits - 1)) != 0) raw -= 1 << bits;
    }
    return raw * scale + offset;
  }

  String decodeText(List<int> data) {
    if (type == 'ascii') {
      final end = (start + (length <= 1 ? data.length : length)).clamp(0, data.length);
      if (start >= end) return '';
      return String.fromCharCodes(
              data.sublist(start, end).where((b) => b >= 0x20 && b < 0x7F))
          .trim();
    }
    if (type == 'hex') {
      final end = (start + (length <= 1 ? data.length : length)).clamp(0, data.length);
      return start >= end ? '' : toHex(data.sublist(start, end));
    }
    if (type == 'date') {
      // BCD day, month, year (2 bytes) and optionally hour, minute.
      if (data.length < start + 4) return '—';
      final d = data.sublist(start);
      String two(int b) => bcdDecode(b).toString().padLeft(2, '0');
      final date = '${two(d[0])}.${two(d[1])}.${two(d[2])}${two(d[3])}';
      return length >= 6 && d.length >= 6 ? '$date ${two(d[4])}:${two(d[5])}' : date;
    }
    final v = decodeNumber(data);
    if (v == null) return '—';
    if (type == 'enum') return labels[v.round()] ?? v.round().toString();
    return v.toStringAsFixed(decimals);
  }
}

class IdentField {
  IdentField({required this.id, required this.name, required this.ident, required this.encoding, this.unit = ''});

  factory IdentField.fromJson(Map<String, dynamic> j) => IdentField(
        id: j['id'],
        name: j['name'],
        ident: parseIntFlexible(j['ident']),
        encoding: ValueEncoding.fromJson(j['encoding'] ?? {'type': 'ascii'}),
        unit: j['unit'] ?? '',
      );

  final String id;
  final String name;
  final int ident;
  final ValueEncoding encoding;
  final String unit;

  String format(List<int> data) {
    final t = encoding.decodeText(data);
    return unit.isEmpty || t == '—' ? t : '$t $unit';
  }
}

class LiveValueDef {
  LiveValueDef({
    required this.id,
    required this.name,
    required this.ident,
    required this.encoding,
    this.unit = '',
    this.min,
    this.max,
    this.basic = false,
    this.group = 'General',
    this.userDefined = false,
  });

  factory LiveValueDef.fromJson(Map<String, dynamic> j) => LiveValueDef(
        id: j['id'],
        name: j['name'],
        ident: parseIntFlexible(j['ident']),
        encoding: ValueEncoding.fromJson(j['encoding']),
        unit: j['unit'] ?? '',
        min: (j['min'] as num?)?.toDouble(),
        max: (j['max'] as num?)?.toDouble(),
        basic: j['basic'] ?? false,
        group: j['group'] ?? 'General',
        userDefined: j['userDefined'] ?? false,
      );

  final String id;
  final String name;
  final int ident;
  final ValueEncoding encoding;
  final String unit;
  final double? min;
  final double? max;

  /// Available on the Free tier.
  final bool basic;
  final String group;
  final bool userDefined;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ident': '0x${hexWord(ident, digits: ident > 0xFF ? 4 : 2)}',
        'encoding': encoding.toJson(),
        'unit': unit,
        if (min != null) 'min': min,
        if (max != null) 'max': max,
        if (basic) 'basic': true,
        'group': group,
        if (userDefined) 'userDefined': true,
      };
}

class CodingOption {
  CodingOption(this.value, this.label, [this.description]);
  factory CodingOption.fromJson(Map<String, dynamic> j) =>
      CodingOption(parseIntFlexible(j['value']), j['label'], j['description']);
  final int value;
  final String label;
  final String? description;
}

/// A setting that must change together with this one in another ECU (e.g.
/// switching TPMS off needs both ZFE and the instrument cluster).
class LinkedSetting {
  LinkedSetting({required this.ecu, required this.param, required this.valueMap});
  factory LinkedSetting.fromJson(Map<String, dynamic> j) => LinkedSetting(
        ecu: j['ecu'],
        param: j['param'],
        valueMap: {
          for (final e in (j['map'] as Map).entries) parseIntFlexible(e.key): parseIntFlexible(e.value),
        },
      );
  final String ecu;
  final String param;
  final Map<int, int> valueMap;
}

class CodingParam {
  CodingParam({
    required this.id,
    required this.name,
    required this.byte,
    required this.mask,
    required this.options,
    this.description = '',
    this.risk = Risk.low,
    this.warning,
    this.linked = const [],
  });

  factory CodingParam.fromJson(Map<String, dynamic> j) => CodingParam(
        id: j['id'],
        name: j['name'],
        description: j['description'] ?? '',
        byte: j['byte'],
        mask: parseIntFlexible(j['mask']),
        options: _list(j['options']).map(CodingOption.fromJson).toList(),
        risk: _enum(Risk.values, j['risk'], Risk.low),
        warning: j['warning'],
        linked: _list(j['linked']).map(LinkedSetting.fromJson).toList(),
      );

  final String id;
  final String name;
  final String description;
  final int byte;
  final int mask;
  final List<CodingOption> options;
  final Risk risk;
  final String? warning;
  final List<LinkedSetting> linked;

  int read(List<int> block) => block[byte] & mask;

  List<int> apply(List<int> block, int value) {
    final out = List<int>.of(block);
    out[byte] = (out[byte] & ~mask & 0xFF) | (value & mask);
    return out;
  }

  CodingOption? optionFor(int value) {
    for (final o in options) {
      if (o.value == value) return o;
    }
    return null;
  }
}

class CodingBlock {
  CodingBlock({
    required this.id,
    required this.name,
    required this.ident,
    required this.length,
    required this.params,
  });

  factory CodingBlock.fromJson(Map<String, dynamic> j) => CodingBlock(
        id: j['id'],
        name: j['name'],
        ident: parseIntFlexible(j['ident']),
        length: j['length'],
        params: _list(j['params']).map(CodingParam.fromJson).toList(),
      );

  final String id;
  final String name;
  final int ident;
  final int length;
  final List<CodingParam> params;
}

class ProcedureInput {
  ProcedureInput({
    required this.id,
    required this.label,
    required this.defaultValue,
    this.min = 0,
    this.max = 999999,
    this.step = 1,
    this.unit = '',
  });

  factory ProcedureInput.fromJson(Map<String, dynamic> j) => ProcedureInput(
        id: j['id'],
        label: j['label'],
        defaultValue: j['default'] ?? 0,
        min: j['min'] ?? 0,
        max: j['max'] ?? 999999,
        step: j['step'] ?? 1,
        unit: j['unit'] ?? '',
      );

  final String id;
  final String label;
  final int defaultValue;
  final int min;
  final int max;
  final int step;
  final String unit;
}

/// One operation in a procedure. See [ProcedureRunner] for semantics.
class ProcedureStep {
  ProcedureStep({
    required this.op,
    this.ident,
    this.data,
    this.control,
    this.param,
    this.value,
    this.ms,
    this.message,
    this.label,
  });

  factory ProcedureStep.fromJson(Map<String, dynamic> j) => ProcedureStep(
        op: j['op'],
        ident: _int(j['ident']),
        data: j['data'],
        control: _int(j['control']),
        param: _int(j['param']),
        value: _int(j['value']),
        ms: j['ms'],
        message: j['message'],
        label: j['label'],
      );

  /// `session`, `security`, `write`, `verify`, `read`, `routine`, `io`,
  /// `wait`, `prompt`, `reset`, `clearDtcs`, `hold`.
  ///
  /// `hold` drives an actuator (like `io`) and keeps re-asserting it until the
  /// rider taps Stop, then returns control to the ECU. Used to hold the
  /// exhaust flap open for a dyno run or a bench check.
  final String op;
  final int? ident;
  final String? data;
  final int? control;
  final int? param;
  final int? value;
  final int? ms;
  final String? message;
  final String? label;
}

class Preconditions {
  const Preconditions({
    this.ignitionOn = true,
    this.engineOff = true,
    this.engineRunning = false,
    this.minVoltage = 12.0,
    this.extra = const [],
  });

  factory Preconditions.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const Preconditions();
    return Preconditions(
      ignitionOn: j['ignitionOn'] ?? true,
      engineOff: j['engineOff'] ?? true,
      engineRunning: j['engineRunning'] ?? false,
      minVoltage: _num(j['minVoltage'], 12.0),
      extra: (j['extra'] as List? ?? const []).cast<String>(),
    );
  }

  final bool ignitionOn;
  final bool engineOff;
  final bool engineRunning;
  final double minVoltage;
  final List<String> extra;
}

class ProcedureDef {
  ProcedureDef({
    required this.id,
    required this.name,
    required this.kind,
    required this.steps,
    this.description = '',
    Tier? tier,
    this.verified = false,
    this.needsLongMessages = false,
    this.preconditions = const Preconditions(),
    this.inputs = const [],
    this.statusReads = const [],
    this.successMessage,
    this.offRoadOnly = false,
  }) : tier = tier ?? kind.defaultTier;

  factory ProcedureDef.fromJson(Map<String, dynamic> j) {
    final kind = _enum(ProcedureKind.values, j['kind'], ProcedureKind.actuator);
    return ProcedureDef(
      id: j['id'],
      name: j['name'],
      kind: kind,
      description: j['description'] ?? '',
      tier: j['tier'] == null ? null : _enum(Tier.values, j['tier'], kind.defaultTier),
      verified: j['verified'] ?? false,
      needsLongMessages: j['needsLongMessages'] ?? false,
      preconditions: Preconditions.fromJson(j['preconditions']),
      inputs: _list(j['inputs']).map(ProcedureInput.fromJson).toList(),
      steps: _list(j['steps']).map(ProcedureStep.fromJson).toList(),
      statusReads: _list(j['status']).map(IdentField.fromJson).toList(),
      successMessage: j['successMessage'],
      offRoadOnly: j['offRoadOnly'] ?? false,
    );
  }

  final String id;
  final String name;
  final ProcedureKind kind;
  final String description;
  final Tier tier;
  final bool verified;
  final bool needsLongMessages;
  final Preconditions preconditions;
  final List<ProcedureInput> inputs;
  final List<ProcedureStep> steps;

  /// Values shown before/after running (e.g. current service due date).
  final List<IdentField> statusReads;
  final String? successMessage;

  /// Closed-course / off-road only. Blocked unless the rider has turned on
  /// track mode and accepted that it isn't for road use. It never hides a
  /// fault or changes what the ECU monitors; the ECU resumes control when the
  /// procedure ends.
  final bool offRoadOnly;

  bool get writes =>
      steps.any((s) => const {'write', 'routine', 'io', 'reset', 'clearDtcs', 'hold'}.contains(s.op));
}

class SecurityDef {
  SecurityDef({required this.level, required this.algorithm, this.session = 0x03});
  factory SecurityDef.fromJson(Map<String, dynamic> j) => SecurityDef(
        level: _int(j['level']) ?? 1,
        algorithm: j['algorithm'],
        session: _int(j['session']) ?? 0x03,
      );
  final int level;
  final String algorithm;
  final int session;
}

class EcuDef {
  EcuDef({
    required this.id,
    required this.name,
    required this.shortName,
    required this.address,
    required this.protocol,
    this.category = 'other',
    this.verified = false,
    this.identification = const [],
    List<LiveValueDef>? liveData,
    this.coding = const [],
    this.procedures = const [],
    this.security,
    this.writeSession,
    this.dtcText = const {},
  }) : liveData = liveData ?? [];

  factory EcuDef.fromJson(Map<String, dynamic> j) => EcuDef(
        id: j['id'],
        name: j['name'],
        shortName: j['shortName'] ?? j['id'].toString().toUpperCase(),
        address: parseIntFlexible(j['address']),
        protocol: _enum(EcuProtocol.values, j['protocol'], EcuProtocol.uds),
        category: j['category'] ?? 'other',
        verified: j['verified'] ?? false,
        identification: _list(j['identification']).map(IdentField.fromJson).toList(),
        liveData: _list(j['liveData']).map(LiveValueDef.fromJson).toList(),
        coding: _list(j['coding']).map(CodingBlock.fromJson).toList(),
        procedures: _list(j['procedures']).map(ProcedureDef.fromJson).toList(),
        security: j['security'] == null ? null : SecurityDef.fromJson(j['security']),
        writeSession: _int(j['writeSession']),
        dtcText: {
          for (final e in (j['dtcText'] as Map? ?? const {}).entries)
            e.key.toString().toUpperCase(): e.value as String,
        },
      );

  final String id;
  final String name;
  final String shortName;
  final int address;
  final EcuProtocol protocol;

  /// `engine`, `abs`, `cluster`, `body`, `chassis`, `tpms`, `obd`, `other`.
  final String category;

  /// True once the address and identifiers were confirmed on a real bike (or
  /// on the simulator for demo profiles).
  final bool verified;
  final List<IdentField> identification;
  final List<LiveValueDef> liveData;
  final List<CodingBlock> coding;
  final List<ProcedureDef> procedures;
  final SecurityDef? security;

  /// Diagnostic session used before writes (defaults per protocol).
  final int? writeSession;
  final Map<String, String> dtcText;

  int get effectiveWriteSession => writeSession ?? (protocol == EcuProtocol.kwp ? 0x86 : 0x03);

  BusTarget get target => switch (protocol) {
        EcuProtocol.kwp => BusTarget(AddressingMode.kLine, address),
        EcuProtocol.uds => BusTarget(AddressingMode.canExtended, address),
        EcuProtocol.obd => const BusTarget(AddressingMode.canObd, 0x7DF),
      };

  CodingParam? findParam(String id) {
    for (final b in coding) {
      for (final p in b.params) {
        if (p.id == id) return p;
      }
    }
    return null;
  }

  CodingBlock? blockOf(CodingParam p) {
    for (final b in coding) {
      if (b.params.contains(p)) return b;
    }
    return null;
  }
}

class BikeProfile {
  BikeProfile({
    required this.id,
    required this.name,
    required this.bus,
    required this.ecus,
    this.models = const [],
    this.years = '',
    this.simulator = false,
    this.notes = '',
  });

  factory BikeProfile.fromJson(Map<String, dynamic> j) => BikeProfile(
        id: j['id'],
        name: j['name'],
        bus: j['bus'] ?? 'can',
        models: (j['models'] as List? ?? const []).cast<String>(),
        years: j['years'] ?? '',
        simulator: j['simulator'] ?? false,
        notes: j['notes'] ?? '',
        ecus: _list(j['ecus']).map(EcuDef.fromJson).toList(),
      );

  static BikeProfile parse(String source) => BikeProfile.fromJson(jsonDecode(source));

  final String id;
  final String name;

  /// `can` or `kline`.
  final String bus;
  final List<String> models;
  final String years;
  final bool simulator;
  final String notes;
  final List<EcuDef> ecus;

  bool get isKLine => bus == 'kline';

  EcuDef? ecu(String id) {
    for (final e in ecus) {
      if (e.id == id) return e;
    }
    return null;
  }

  Iterable<(EcuDef, ProcedureDef)> get procedures sync* {
    for (final e in ecus) {
      for (final p in e.procedures) {
        yield (e, p);
      }
    }
  }
}
