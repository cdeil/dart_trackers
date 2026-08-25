import 'dart:math' as math;
import 'dart:typed_data';

/// Small row-major float64 matrix used by the tracker math.
class Matrix {
  final int rows;
  final int cols;
  final Float64List data;

  new(this.rows, this.cols, [Float64List? data])
    : data = data == null
          ? Float64List(rows * cols)
          : Float64List.fromList(data) {
    if (rows < 0 || cols < 0) {
      throw ArgumentError('Matrix dimensions must be non-negative');
    }
    if (this.data.length != rows * cols) {
      throw ArgumentError.value(
        this.data.length,
        'data.length',
        'Expected ${rows * cols}',
      );
    }
  }

  factory identity(int size) {
    final result = Matrix(size, size);
    for (var i = 0; i < size; i++) {
      result[i][i] = 1.0;
    }
    return result;
  }

  factory fromRows(List<List<num>> rows) {
    if (rows.isEmpty) {
      return Matrix(0, 0);
    }
    final cols = rows.first.length;
    final flat = Float64List(rows.length * cols);
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].length != cols) {
        throw ArgumentError('All rows must have the same length');
      }
      for (var j = 0; j < cols; j++) {
        flat[i * cols + j] = rows[i][j].toDouble();
      }
    }
    return Matrix(rows.length, cols, flat);
  }

  factory column(List<num> values) {
    return Matrix(
      values.length,
      1,
      Float64List.fromList(values.map((v) => v.toDouble()).toList()),
    );
  }

  MatrixRow operator [](int row) {
    if (row < 0 || row >= rows) {
      throw RangeError.index(row, this, 'row', null, rows);
    }
    return MatrixRow(this, row);
  }

  double getAt(int row, int col) => data[row * cols + col];

  void setAt(int row, int col, double value) {
    data[row * cols + col] = value;
  }

  Matrix copy() => Matrix(rows, cols, data);

  Matrix transpose() {
    final result = Matrix(cols, rows);
    for (var i = 0; i < rows; i++) {
      for (var j = 0; j < cols; j++) {
        result[j][i] = this[i][j];
      }
    }
    return result;
  }

  Matrix operator +(Matrix other) {
    _checkSameShape(other);
    final result = Matrix(rows, cols);
    for (var i = 0; i < data.length; i++) {
      result.data[i] = data[i] + other.data[i];
    }
    return result;
  }

  Matrix operator -(Matrix other) {
    _checkSameShape(other);
    final result = Matrix(rows, cols);
    for (var i = 0; i < data.length; i++) {
      result.data[i] = data[i] - other.data[i];
    }
    return result;
  }

  Matrix operator *(Matrix other) => matMul(other);

  Matrix matMul(Matrix other) {
    if (cols != other.rows) {
      throw ArgumentError(
        'Matrix shape mismatch: $rows x $cols cannot multiply ${other.rows} x ${other.cols}',
      );
    }
    final result = Matrix(rows, other.cols);
    for (var i = 0; i < rows; i++) {
      for (var k = 0; k < cols; k++) {
        final a = getAt(i, k);
        if (a == 0.0) continue;
        for (var j = 0; j < other.cols; j++) {
          result.data[i * other.cols + j] += a * other.getAt(k, j);
        }
      }
    }
    return result;
  }

  Matrix scaled(double factor) {
    final result = Matrix(rows, cols);
    for (var i = 0; i < data.length; i++) {
      result.data[i] = data[i] * factor;
    }
    return result;
  }

  Matrix inverse() {
    if (rows != cols) {
      throw ArgumentError('Only square matrices can be inverted');
    }
    final n = rows;
    final a = copy();
    final inv = Matrix.identity(n);

    for (var col = 0; col < n; col++) {
      var pivot = col;
      var pivotAbs = a[col][col].abs();
      for (var row = col + 1; row < n; row++) {
        final candidate = a[row][col].abs();
        if (candidate > pivotAbs) {
          pivotAbs = candidate;
          pivot = row;
        }
      }
      if (pivotAbs < 1e-15) {
        throw ArgumentError('Matrix is singular or ill-conditioned');
      }
      if (pivot != col) {
        a._swapRows(pivot, col);
        inv._swapRows(pivot, col);
      }

      final pivotValue = a[col][col];
      for (var j = 0; j < n; j++) {
        a[col][j] /= pivotValue;
        inv[col][j] /= pivotValue;
      }

      for (var row = 0; row < n; row++) {
        if (row == col) continue;
        final factor = a[row][col];
        if (factor == 0.0) continue;
        for (var j = 0; j < n; j++) {
          a[row][j] -= factor * a[col][j];
          inv[row][j] -= factor * inv[col][j];
        }
      }
    }
    return inv;
  }

  List<double> columnToList() {
    if (cols != 1) {
      throw StateError('Matrix is not a column vector');
    }
    return List<double>.from(data);
  }

  List<List<double>> toRows() {
    return List.generate(rows, (i) => List.generate(cols, (j) => getAt(i, j)));
  }

  bool closeTo(
    Matrix other, {
    double absoluteTolerance = 1e-9,
    double relativeTolerance = 1e-7,
  }) {
    _checkSameShape(other);
    for (var i = 0; i < data.length; i++) {
      final a = data[i];
      final b = other.data[i];
      final tol =
          absoluteTolerance + relativeTolerance * math.max(a.abs(), b.abs());
      if ((a - b).abs() > tol) return false;
    }
    return true;
  }

  void _checkSameShape(Matrix other) {
    if (rows != other.rows || cols != other.cols) {
      throw ArgumentError(
        'Matrix shape mismatch: $rows x $cols vs ${other.rows} x ${other.cols}',
      );
    }
  }

  void _swapRows(int a, int b) {
    for (var j = 0; j < cols; j++) {
      final tmp = this[a][j];
      this[a][j] = this[b][j];
      this[b][j] = tmp;
    }
  }
}

class MatrixRow {
  final Matrix matrix;
  final int row;

  new(this.matrix, this.row);

  double operator [](int col) {
    if (col < 0 || col >= matrix.cols) {
      throw RangeError.index(col, matrix, 'col', null, matrix.cols);
    }
    return matrix.data[row * matrix.cols + col];
  }

  void operator []=(int col, double value) {
    if (col < 0 || col >= matrix.cols) {
      throw RangeError.index(col, matrix, 'col', null, matrix.cols);
    }
    matrix.data[row * matrix.cols + col] = value;
  }
}
