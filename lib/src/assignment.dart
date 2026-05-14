import 'matrix.dart';

class LinearAssignmentResult {
  final List<int> rowIndices;
  final List<int> colIndices;

  const LinearAssignmentResult({
    required this.rowIndices,
    required this.colIndices,
  });

  double totalCost(Matrix costMatrix) {
    var result = 0.0;
    for (var i = 0; i < rowIndices.length; i++) {
      result += costMatrix[rowIndices[i]][colIndices[i]];
    }
    return result;
  }
}

/// Rectangular shortest augmenting path assignment.
///
/// This is a small Dart port of the algorithm used by SciPy's
/// `linear_sum_assignment` implementation. Ties are deterministic but should
/// not be treated as a public semantic contract for tracker IDs.
LinearAssignmentResult linearSumAssignment(
  Matrix costMatrix, {
  bool maximize = false,
}) {
  var nr = costMatrix.rows;
  var nc = costMatrix.cols;
  if (nr == 0 || nc == 0) {
    return const LinearAssignmentResult(rowIndices: [], colIndices: []);
  }

  var workingCost = costMatrix.copy();
  var transposed = false;
  if (nc < nr) {
    workingCost = workingCost.transpose();
    final tmp = nr;
    nr = nc;
    nc = tmp;
    transposed = true;
  }

  for (var i = 0; i < nr; i++) {
    for (var j = 0; j < nc; j++) {
      final value = workingCost[i][j];
      if (value.isNaN || value == double.negativeInfinity) {
        throw ArgumentError('Cost matrix contains invalid numeric entries');
      }
      if (maximize) {
        workingCost[i][j] = -value;
      }
    }
  }

  final result = _solveAssignment(workingCost, nr, nc);
  if (!transposed) {
    return result;
  }

  final pairs = <(int, int)>[];
  for (var i = 0; i < result.rowIndices.length; i++) {
    pairs.add((result.colIndices[i], result.rowIndices[i]));
  }
  pairs.sort((a, b) => a.$1.compareTo(b.$1));
  return LinearAssignmentResult(
    rowIndices: [for (final pair in pairs) pair.$1],
    colIndices: [for (final pair in pairs) pair.$2],
  );
}

LinearAssignmentResult _solveAssignment(Matrix cost, int nr, int nc) {
  final u = List<double>.filled(nr, 0.0);
  final v = List<double>.filled(nc, 0.0);
  final col4row = List<int>.filled(nr, -1);
  final row4col = List<int>.filled(nc, -1);
  final shortestPathCosts = List<double>.filled(nc, 0.0);
  final path = List<int>.filled(nc, -1);
  final scannedRows = List<bool>.filled(nr, false);
  final scannedCols = List<bool>.filled(nc, false);
  final remaining = List<int>.filled(nc, 0);

  for (var curRow = 0; curRow < nr; curRow++) {
    final pathResult = _augmentingPath(
      cost,
      nc,
      u,
      v,
      path,
      row4col,
      shortestPathCosts,
      curRow,
      scannedRows,
      scannedCols,
      remaining,
    );
    final minVal = pathResult.$1;
    var sink = pathResult.$2;
    if (sink < 0) {
      throw StateError('Cost matrix is infeasible');
    }

    u[curRow] += minVal;
    for (var i = 0; i < nr; i++) {
      if (scannedRows[i] && i != curRow && col4row[i] != -1) {
        u[i] += minVal - shortestPathCosts[col4row[i]];
      }
    }
    for (var j = 0; j < nc; j++) {
      if (scannedCols[j]) {
        v[j] -= minVal - shortestPathCosts[j];
      }
    }

    while (true) {
      final i = path[sink];
      row4col[sink] = i;
      final temp = col4row[i];
      col4row[i] = sink;
      sink = temp;
      if (i == curRow) break;
    }
  }

  final rows = <int>[];
  final cols = <int>[];
  for (var i = 0; i < nr; i++) {
    if (col4row[i] != -1) {
      rows.add(i);
      cols.add(col4row[i]);
    }
  }
  return LinearAssignmentResult(rowIndices: rows, colIndices: cols);
}

(double, int) _augmentingPath(
  Matrix cost,
  int nc,
  List<double> u,
  List<double> v,
  List<int> path,
  List<int> row4col,
  List<double> shortestPathCosts,
  int startRow,
  List<bool> scannedRows,
  List<bool> scannedCols,
  List<int> remaining,
) {
  var minVal = 0.0;
  var numRemaining = nc;
  for (var it = 0; it < nc; it++) {
    remaining[it] = nc - it - 1;
    scannedCols[it] = false;
    shortestPathCosts[it] = double.infinity;
  }
  for (var i = 0; i < scannedRows.length; i++) {
    scannedRows[i] = false;
  }

  var sink = -1;
  var currentRow = startRow;
  while (sink == -1) {
    var index = -1;
    var lowest = double.infinity;
    scannedRows[currentRow] = true;
    for (var it = 0; it < numRemaining; it++) {
      final j = remaining[it];
      final reducedCost = minVal + cost[currentRow][j] - u[currentRow] - v[j];
      if (reducedCost < shortestPathCosts[j]) {
        path[j] = currentRow;
        shortestPathCosts[j] = reducedCost;
      }
      if (shortestPathCosts[j] < lowest ||
          (shortestPathCosts[j] == lowest && row4col[j] == -1)) {
        lowest = shortestPathCosts[j];
        index = it;
      }
    }

    minVal = lowest;
    if (minVal == double.infinity || index < 0) {
      return (-1.0, -1);
    }

    final j = remaining[index];
    if (row4col[j] == -1) {
      sink = j;
    } else {
      currentRow = row4col[j];
    }
    scannedCols[j] = true;
    remaining[index] = remaining[numRemaining - 1];
    numRemaining--;
  }

  return (minVal, sink);
}
