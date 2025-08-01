import numpy as np

from pymoo.nds.cpp_non_dominated_sorting import fast_non_dominated_sort
from pymoo.nds.dominator import Dominator


class NonDominatedSorting:

    def __init__(self, epsilon=0.0, method="fast_non_dominated_sort") -> None:
        super().__init__()
        self.epsilon = float(epsilon)
        self.method = method

    def do(self, F, return_rank=False, only_non_dominated_front=False, n_stop_if_ranked=None):

        # if not set just set it to a very large values because the cython algorithms do not take None
        if n_stop_if_ranked is None:
            n_stop_if_ranked = int(1e8)

        if self.method == 'fast_non_dominated_sort':
            func = fast_non_dominated_sort
        else:
            raise Exception("Unknown non-dominated sorting method: %s" % self.method)

        fronts = func(F, epsilon=self.epsilon)

        # convert to numpy array for each front and filter by n_stop_if_ranked if desired
        _fronts = []
        n_ranked = 0
        for front in fronts:

            _fronts.append(np.array(front, dtype=int))

            # increment the n_ranked solution counter
            n_ranked += len(front)

            # stop if more than this solutions are n_ranked
            if n_ranked >= n_stop_if_ranked:
                break

        fronts = _fronts

        if only_non_dominated_front:
            return fronts[0]

        if return_rank:
            rank = rank_from_fronts(fronts, F.shape[0])
            return fronts, rank

        return fronts


def rank_from_fronts(fronts, n):
    # create the rank array and set values
    rank = np.full(n, 1e16, dtype=int)
    for i, front in enumerate(fronts):
        rank[front] = i

    return rank

# Returns all indices of F that are not dominated by the other objective values
def find_non_dominated(F, _F=None):
    m = Dominator.calc_domination_matrix(F, _F)
    i = np.where(np.all(m >= 0, axis=1))[0]
    return i
