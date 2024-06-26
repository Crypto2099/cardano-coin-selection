-- |
-- Copyright: © 2018-2024 Intersect MBO
-- License: Apache-2.0
--
-- __Submodules__ of this module provide implementations of
-- __coin selection algorithms__.
--
-- Algorithms can be divided into two categories:
--
--  * <#generalized-algorithms Generalized Algorithms>
--
--        Algorithms that implement the general
--        'Cardano.CoinSelection.CoinSelectionAlgorithm' interface.
--
--  * <#specialized-algorithms Specialized Algorithms>
--
--        Algorithms that provide functionality suited to specialized purposes.
--
-- = Generalized Algorithms #generalized-algorithms#
--
-- The following algorithms implement the general
-- 'Cardano.CoinSelection.CoinSelectionAlgorithm' interface:
--
--  * __"Cardano.CoinSelection.Algorithm.LargestFirst"__
--
--        Provides an implementation of the __Largest-First__ algorithm.
--
--        When selecting inputs from a given set of UTxO entries, this
--        algorithm always selects the /largest/ entries /first/.
--
--   * __"Cardano.CoinSelection.Algorithm.RandomImprove"__
--
--        Provides an implementation of the __Random-Improve__ algorithm.
--
--        When selecting inputs from a given set of UTxO entries, this
--        algorithm always selects entries at /random/.
--
--        Once selections have been made, a second phase attempts to /improve/
--        on each of the existing selections in order to optimize change
--        outputs.
--
-- For __guidance on choosing an algorithm__ that's appropriate for your
-- scenario, please consult the following article:
--
--        <https://iohk.io/en/blog/posts/2018/07/03/self-organisation-in-coin-selection/>
--
-- = Specialized Algorithms #specialized-algorithms#
--
-- The following algorithms provide functionality suited to specialized
-- purposes:
--
--   * __"Cardano.CoinSelection.Algorithm.Migration"__
--
--        Provides an algorithm for migrating all funds from one wallet to
--        another.
--
module Cardano.CoinSelection.Algorithm where
