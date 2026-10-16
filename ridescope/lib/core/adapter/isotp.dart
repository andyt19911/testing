/// Reassembles ISO 15765-2 (ISO-TP) frames as printed by an ELM327 with
/// headers on (`ATH1`), where every CAN frame shows its PCI byte.
///
/// With BMW extended addressing the first data byte of each frame is the
/// address of the receiver (`F1` for the tester) and the PCI follows it.
class IsoTpAssembler {
  IsoTpAssembler({required this.extendedAddressing});

  final bool extendedAddressing;
  final Map<int, _Partial> _partials = {};
  final List<CanMessage> completed = [];

  /// Feeds one CAN frame. Frames that are not part of a valid sequence are
  /// ignored; consecutive-frame sequence errors drop the partial message.
  void addFrame(int canId, List<int> frame) {
    var i = 0;
    int? ext;
    if (extendedAddressing) {
      if (frame.isEmpty) return;
      ext = frame[0];
      i = 1;
    }
    if (frame.length <= i) return;
    final pci = frame[i];
    final type = pci >> 4;
    switch (type) {
      case 0: // single frame
        final len = pci & 0x0F;
        if (len == 0 || frame.length < i + 1 + len) return;
        completed.add(CanMessage(canId, frame.sublist(i + 1, i + 1 + len), ext));
        break;
      case 1: // first frame
        if (frame.length < i + 2) return;
        final len = ((pci & 0x0F) << 8) | frame[i + 1];
        _partials[canId] = _Partial(len, ext)..data.addAll(frame.sublist(i + 2));
        _finishIfDone(canId);
        break;
      case 2: // consecutive frame
        final p = _partials[canId];
        if (p == null) return;
        final seq = pci & 0x0F;
        if (seq != p.nextSeq) {
          _partials.remove(canId);
          return;
        }
        p.nextSeq = (p.nextSeq + 1) & 0x0F;
        p.data.addAll(frame.sublist(i + 1));
        _finishIfDone(canId);
        break;
      default: // flow control (3) or invalid: not data
        break;
    }
  }

  void _finishIfDone(int canId) {
    final p = _partials[canId]!;
    if (p.data.length >= p.length) {
      completed.add(CanMessage(canId, p.data.sublist(0, p.length), p.ext));
      _partials.remove(canId);
    }
  }

  bool get hasIncomplete => _partials.isNotEmpty;
}

class _Partial {
  _Partial(this.length, this.ext);
  final int length;
  final int? ext;
  final List<int> data = [];
  int nextSeq = 1;
}

class CanMessage {
  CanMessage(this.canId, this.data, this.extAddress);
  final int canId;
  final List<int> data;
  final int? extAddress;
}

/// Splits [payload] into ISO-TP frames (used by the simulator and by STN
/// adapters that need pre-segmented frames).
List<List<int>> segmentIsoTp(List<int> payload, {int? extAddress}) {
  final prefix = extAddress == null ? <int>[] : [extAddress];
  final cap = 8 - prefix.length;
  if (payload.length <= cap - 1) {
    return [
      [...prefix, payload.length, ...payload]
    ];
  }
  final frames = <List<int>>[];
  final firstData = cap - 2;
  frames.add([
    ...prefix,
    0x10 | ((payload.length >> 8) & 0x0F),
    payload.length & 0xFF,
    ...payload.sublist(0, firstData),
  ]);
  var offset = firstData;
  var seq = 1;
  while (offset < payload.length) {
    final end = (offset + cap - 1).clamp(0, payload.length);
    frames.add([...prefix, 0x20 | seq, ...payload.sublist(offset, end)]);
    offset = end;
    seq = (seq + 1) & 0x0F;
  }
  return frames;
}
