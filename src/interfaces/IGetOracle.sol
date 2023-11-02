// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import { IChainlinkRWAOracle } from "@tangible/interfaces/IChainlinkRWAOracle.sol";

interface IGetOracle {
    function chainlinkRWAOracle() external view returns (IChainlinkRWAOracle);
}