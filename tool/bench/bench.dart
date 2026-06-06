import 'dart:math';

import 'package:diffutil_dart/diffutil.dart';

// Benchmark harness inspired by:
// https://mrale.ph/blog/2021/01/21/microbenchmarking-dart-part-1.html
// https://mrale.ph/blog/2024/11/27/microbenchmarks-are-experiments.html
//
// Run with AOT to avoid JIT effects:
//   dart compile exe tool/bench/bench.dart -o build/diff_bench
//   ./build/diff_bench

const _sizes = [10, 100, 1000, 10000];
const _diffKinds = ['none', 'few', 'many'];
const _types = ['int', 'object'];

int _blackHole = 0;

class _BenchCase<T> {
  final String name;
  final List<T> oldList;
  final List<T> newList;
  final bool detectMoves;

  _BenchCase({
    required this.name,
    required this.oldList,
    required this.newList,
    required this.detectMoves,
  });

  int runOnce() {
    final result = calculateListDiff<T>(
      oldList,
      newList,
      detectMoves: detectMoves,
    );
    int checksum = 0;
    for (final update in result.getUpdates(batch: true)) {
      checksum = (checksum + update.hashCode) & 0x7fffffff;
    }
    return checksum;
  }
}

List<int> _baseIntList(int size) => List<int>.generate(size, (i) => i);

List<int> _applyFewIntDiffs(List<int> base) {
  final size = base.length;
  final result = List<int>.from(base);
  final changes = max(1, size ~/ 100);
  final step = max(1, size ~/ changes);
  for (var i = 0; i < changes; i++) {
    final idx = (i * step) % size;
    result[idx] = base[idx] + size * 10 + i;
  }
  return result;
}

List<int> _applyManyIntDiffs(List<int> base) {
  final size = base.length;
  return List<int>.generate(size, (i) => base[i] + size * 10);
}

class BenchItem {
  final int a;
  final int b;
  final int c;
  final int d;
  final bool e;
  final bool f;
  final String g;
  final String h;

  const BenchItem({
    required this.a,
    required this.b,
    required this.c,
    required this.d,
    required this.e,
    required this.f,
    required this.g,
    required this.h,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BenchItem &&
          runtimeType == other.runtimeType &&
          a == other.a &&
          b == other.b &&
          c == other.c &&
          d == other.d &&
          e == other.e &&
          f == other.f &&
          g == other.g &&
          h == other.h;

  @override
  int get hashCode => Object.hash(a, b, c, d, e, f, g, h);
}

BenchItem _itemForIndex(int index, {int variant = 0}) {
  final salt = variant == 0 ? 0 : 1000003;
  return BenchItem(
    a: index,
    b: index * 31 + salt,
    c: (index ^ 0x9e3779b9) + salt,
    d: index + 12345 + salt,
    e: ((index + variant) & 1) == 0,
    f: ((index + variant) & 2) == 0,
    g: 'g${index}_$variant',
    h: 'h${index ^ 0x5a5a5a5a}_$variant',
  );
}

List<BenchItem> _baseItemList(int size) =>
    List<BenchItem>.generate(size, _itemForIndex);

List<BenchItem> _applyFewItemDiffs(List<BenchItem> base) {
  final size = base.length;
  final result = List<BenchItem>.from(base);
  final changes = max(1, size ~/ 100);
  final step = max(1, size ~/ changes);
  for (var i = 0; i < changes; i++) {
    final idx = (i * step) % size;
    result[idx] = _itemForIndex(idx, variant: 1);
  }
  return result;
}

List<BenchItem> _applyManyItemDiffs(int size) =>
    List<BenchItem>.generate(size, (i) => _itemForIndex(i, variant: 1));

int _runLoop<T>(_BenchCase<T> benchCase, int iterations) {
  var local = 0;
  for (var i = 0; i < iterations; i++) {
    local ^= benchCase.runOnce();
  }
  _blackHole ^= local;
  return local;
}

int _calibrateIterations<T>(_BenchCase<T> benchCase, int targetMicros) {
  var iterations = 1;
  while (true) {
    final sw = Stopwatch()..start();
    _runLoop(benchCase, iterations);
    sw.stop();
    final elapsed = sw.elapsedMicroseconds;
    if (elapsed >= targetMicros || iterations >= (1 << 20)) {
      return iterations;
    }
    iterations *= 2;
  }
}

({int iterations, List<double> values}) _measureSamples<T>(
  _BenchCase<T> benchCase, {
  required int warmups,
  required int samples,
  required int targetMicros,
}) {
  final iterations = _calibrateIterations(benchCase, targetMicros);

  for (var i = 0; i < warmups; i++) {
    _runLoop(benchCase, iterations);
  }

  final results = <int>[];
  for (var i = 0; i < samples; i++) {
    final sw = Stopwatch()..start();
    _runLoop(benchCase, iterations);
    sw.stop();
    results.add(sw.elapsedMicroseconds);
  }

  results.sort();
  final microsPerIter = <double>[];
  for (final total in results) {
    microsPerIter.add(total / iterations);
  }
  microsPerIter.sort();

  return (iterations: iterations, values: microsPerIter);
}

double _median(List<double> values) => values[values.length ~/ 2];

String _formatMicros(double micros) => micros.toStringAsFixed(2).padLeft(8);

void main(List<String> args) {
  var detectMoves = false;
  var warmups = 3;
  var samples = 10;
  var targetMicros = 20000;

  for (final arg in args) {
    if (arg == '--detect-moves') {
      detectMoves = true;
    } else if (arg.startsWith('--warmups=')) {
      warmups = int.parse(arg.split('=').last);
    } else if (arg.startsWith('--samples=')) {
      samples = int.parse(arg.split('=').last);
    } else if (arg.startsWith('--target-us=')) {
      targetMicros = int.parse(arg.split('=').last);
    }
  }

  final header = StringBuffer()
    ..writeln('diffutil bench')
    ..writeln('detectMoves: $detectMoves')
    ..writeln('warmups: $warmups samples: $samples target: ${targetMicros}us')
    ..writeln('')
    ..writeln('type   size  diffs  iters      min    median      max');
  print(header.toString());

  for (final size in _sizes) {
    final baseInts = _baseIntList(size);
    final baseItems = _baseItemList(size);

    for (final type in _types) {
      for (final kind in _diffKinds) {
        if (type == 'int') {
          List<int> newList;
          switch (kind) {
            case 'few':
              newList = _applyFewIntDiffs(baseInts);
              break;
            case 'many':
              newList = _applyManyIntDiffs(baseInts);
              break;
            case 'none':
            default:
              newList = List<int>.from(baseInts);
          }

          final benchCase = _BenchCase<int>(
            name: 'type=int size=$size diff=$kind',
            oldList: baseInts,
            newList: newList,
            detectMoves: detectMoves,
          );

          final samplesMicros = _measureSamples(
            benchCase,
            warmups: warmups,
            samples: samples,
            targetMicros: targetMicros,
          );
          final iterations = samplesMicros.iterations;
          final values = samplesMicros.values;
          final min = values.first;
          final med = _median(values);
          final max = values.last;

          print('${type.padRight(6)} '
              '${size.toString().padLeft(5)}  '
              '${kind.padRight(5)}  '
              '${iterations.toString().padLeft(5)}  '
              '${_formatMicros(min)}  '
              '${_formatMicros(med)}  '
              '${_formatMicros(max)}');
        } else {
          List<BenchItem> newList;
          switch (kind) {
            case 'few':
              newList = _applyFewItemDiffs(_baseItemList(size));
              break;
            case 'many':
              newList = _applyManyItemDiffs(size);
              break;
            case 'none':
            default:
              newList = _baseItemList(size);
          }

          final benchCase = _BenchCase<BenchItem>(
            name: 'type=object size=$size diff=$kind',
            oldList: baseItems,
            newList: newList,
            detectMoves: detectMoves,
          );

          final samplesMicros = _measureSamples(
            benchCase,
            warmups: warmups,
            samples: samples,
            targetMicros: targetMicros,
          );
          final iterations = samplesMicros.iterations;
          final values = samplesMicros.values;
          final min = values.first;
          final med = _median(values);
          final max = values.last;

          print('${type.padRight(6)} '
              '${size.toString().padLeft(5)}  '
              '${kind.padRight(5)}  '
              '${iterations.toString().padLeft(5)}  '
              '${_formatMicros(min)}  '
              '${_formatMicros(med)}  '
              '${_formatMicros(max)}');
        }
      }
    }
  }

  if (_blackHole == 42) {
    print('blackhole: $_blackHole');
  }
}
