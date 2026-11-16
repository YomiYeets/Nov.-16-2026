// Small dense linear algebra helpers. The problems in this app are tiny
// (at most 8 unknowns) so simple Gaussian elimination is plenty.

/// Solves A x = b for square A using Gaussian elimination with partial
/// pivoting. Throws [StateError] if A is (numerically) singular.
List<double> solveLinear(List<List<double>> a, List<double> b) {
  final n = b.length;
  // Work on copies: augmented matrix [A | b].
  final m = List.generate(n, (i) => [...a[i], b[i]]);
  for (var col = 0; col < n; col++) {
    // Partial pivoting: swap in the row with the largest entry in this
    // column. This keeps rounding error under control.
    var pivot = col;
    for (var r = col + 1; r < n; r++) {
      if (m[r][col].abs() > m[pivot][col].abs()) pivot = r;
    }
    if (m[pivot][col].abs() < 1e-12) {
      throw StateError('Singular matrix');
    }
    final tmp = m[col];
    m[col] = m[pivot];
    m[pivot] = tmp;
    // Eliminate this column from the rows below.
    for (var r = col + 1; r < n; r++) {
      final f = m[r][col] / m[col][col];
      for (var c = col; c <= n; c++) {
        m[r][c] -= f * m[col][c];
      }
    }
  }
  // Back substitution.
  final x = List<double>.filled(n, 0);
  for (var r = n - 1; r >= 0; r--) {
    var s = m[r][n];
    for (var c = r + 1; c < n; c++) {
      s -= m[r][c] * x[c];
    }
    x[r] = s / m[r][r];
  }
  return x;
}

/// Ordinary least squares: finds the coefficient vector w that minimizes
///   sum_i  weight_i * (rows_i · w - targets_i)^2
/// by solving the "normal equations"  (Xᵀ W X) w = Xᵀ W y.
///
/// With more equations (patches) than unknowns there is no exact solution;
/// this gives the best compromise in the squared-error sense.
List<double> leastSquares(List<List<double>> rows, List<double> targets,
    {List<double>? weights}) {
  final k = rows.first.length;
  final ata = List.generate(k, (_) => List<double>.filled(k, 0));
  final atb = List<double>.filled(k, 0);
  for (var i = 0; i < rows.length; i++) {
    final w = weights?[i] ?? 1.0;
    final r = rows[i];
    for (var p = 0; p < k; p++) {
      atb[p] += w * r[p] * targets[i];
      for (var q = 0; q < k; q++) {
        ata[p][q] += w * r[p] * r[q];
      }
    }
  }
  return solveLinear(ata, atb);
}
