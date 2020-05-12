import 'package:freezed_annotation/freezed_annotation.dart';

part 'diffupdate.freezed.dart';




@freezed
abstract class DiffUpdate with _$DiffUpdate {

  const factory DiffUpdate.insert({int position, int count}) = _Insert;

  const factory DiffUpdate.remove({int position, int count}) = _Remove;

  const factory DiffUpdate.change({int position, Object payload}) = _Change;

  const factory DiffUpdate.move({int from, int to}) = _Move;


}