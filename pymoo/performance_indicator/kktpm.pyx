import numpy as np
cimport numpy as np

class KKTPM:

    def __init__(self, var_bounds_as_constraints=True):
        self.var_bounds_as_constraints = var_bounds_as_constraints

    def calc(self, X, problem, ideal_point=None, utopian_epsilon=1e-4, rho=1e-3):
        """
        Returns the Karush-Kuhn-Tucker Approximate Measure.
        Parameters
        ----------
        X : np.array
        problem : pymoo.model.problem
        ideal_point : np.array
            The ideal point if not in the problem defined or intentionally overwritten.
        utopian_epsilon : float
            The epsilon used for decrease the ideal point to get the utopian point.
        rho : float
            Since augmented achievement scalarization function is used the weight for all other weights
            - here rho - needs to be defined.
        Returns
        -------
        """

        # the final result to be returned
        kktpm = np.full((X.shape[0], 1), np.inf)
        fval = np.full((X.shape[0], 1), np.inf)

        # set the ideal point for normalization
        z = ideal_point

        # if not provided take the one defined in the problem
        if z is None:
            z = problem.ideal_point()
        z -= utopian_epsilon

        # for convenience get the counts directly
        n_solutions, n_var, n_obj, n_constr = X.shape[0], problem.n_var, problem.n_obj, problem.n_constr

        F, CV, G, dF, dG = problem.evaluate(X, return_values_of=["F", "CV", "G", "dF", "dG"])

        # if the measure should include points out of bounds as a constraint
        if self.var_bounds_as_constraints:
            # add the bounds constraints as well
            _G = np.zeros((n_solutions, 2 * n_var))
            _G[:, :n_var] = problem.xl - X
            _G[:, n_var:] = X - problem.xu

            _dG = np.zeros((n_solutions, 2 * n_var, n_var))
            _dG[:, :n_var, :] = - np.eye(n_var)
            _dG[:, n_var:, :] = np.eye(n_var)

            # increase the constraint counter to be correct and change the constraints
            if n_constr > 0:
                G = np.column_stack([G, _G])
                dG = np.column_stack([dG, _dG])
            else:
                G = _G
                dG = _dG

            n_constr = n_constr + 2 * n_var

            problem.set_boundaries_as_constraints(True)
            F_, CV_, G_, dF_, dG_ = problem.evaluate(X, return_values_of=["F", "CV", "G", "dF", "dG"])

            np.testing.assert_allclose(F, F_)
            np.testing.assert_allclose(CV_, CV_)
            np.testing.assert_allclose(dF_, dF_)
            np.testing.assert_allclose(dG, dG_)
            problem.set_boundaries_as_constraints(False)

        # loop through each solution to be considered
        for i in range(n_solutions):

            # get the corresponding values for this solution
            x, f, cv, df = X[i, :], F[i, :], CV[i, :], dF[i, :].swapaxes(1, 0)
            if n_constr > 0:
                g, dg = G[i, :], dG[i].T

            # if the solution that is provided is infeasible
            if cv > 0:
                _kktpm = 1 + cv
                _fval = None

            else:

                w = np.sqrt(np.sum(np.power(f - z, 2))) / (f - z)
                a_m = (df * w + (rho * np.sum(df * w, axis=1))[:, None]).T

                A = np.ones((problem.n_obj, problem.n_obj)) + a_m @ a_m.T
                b = np.ones(problem.n_obj)

                if n_constr > 0:
                    # a_j is just the transpose of the differential of constraints
                    a_j = dg.T

                    # part of the matrix for additional constraints
                    gsq = np.zeros((n_constr, n_constr))
                    np.fill_diagonal(gsq, g * g)

                    # now add the constraints to the optimization problem
                    A = np.vstack([np.hstack([A, a_m @ a_j.T]), np.hstack([a_j @ a_m.T, a_j @ a_j.T + gsq])])
                    b = np.hstack([b, np.zeros(n_constr)])

                method = "qr"
                u = solve(A, b, method=method)

                # until all the lagrange multiplier are positive
                while np.any(u < 0):

                    # go through one by one
                    for j in range(len(u)):

                        # if a lagrange multiplier is negative - we need to fix it
                        if u[j] < 0:
                            # modify the optimization problem
                            A[j, :], A[:, j], A[j, j] = 0, 0, 1
                            b[j] = 0

                            # resolve the problem and redefine u. for sure all preview u[j] are positive now
                            u = solve(A, b, method=method)

                # split up the lagrange multiplier for objective and not
                u_m, u_j = u[:n_obj], u[n_obj:]

                if n_constr > 0:
                    _kktpm = (1 - np.sum(u_m)) ** 2 + np.sum((np.vstack([a_m, a_j]).T @ u) ** 2)
                    _fval = _kktpm + np.sum((u_j * g.T) ** 2)
                else:
                    _kktpm = (1 - np.sum(u_m)) ** 2 + np.sum((a_m.T @ u) ** 2)
                    _fval = _kktpm

                ujgj = -g @ u_j
                if np.sum(u_m) + ujgj * (1 + ujgj) > 1:
                    adjusted_kktpm = - (u_j @ g.T)
                    projected_kktpm = (_kktpm * g @ g.T - g @ u_j) / (1 + g @ g.T)
                    _kktpm = (_kktpm + adjusted_kktpm + projected_kktpm) / 3

            # assign to the values to be returned
            kktpm[i] = _kktpm
            fval[i] = _fval

        return kktpm


def solve(A, b, method="elim"):
    if method == "elim":
        return np.linalg.solve(A, b)

    elif method == "qr":
        Q, R = np.linalg.qr(A)
        y = np.dot(Q.T, b)
        return np.linalg.solve(R, y)

    elif method == "svd":
        U, s, V = np.linalg.svd(A)  # SVD decomposition of A
        A_inv = np.dot(np.dot(V.T, np.linalg.inv(np.diag(s))), U.T)
        return A_inv @ b
