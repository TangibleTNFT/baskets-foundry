// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.9;

library WadMath {
    uint256 internal constant HALF_WAD = 5e17;
    uint256 internal constant WAD = 1e18;

    function rayDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return (b / 2 + a * WAD) / b;
    }

    function rayMul(uint256 a, uint256 b) internal pure returns (uint256) {
        return (HALF_WAD + a * b) / WAD;
    }
}