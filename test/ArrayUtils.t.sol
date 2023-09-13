// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "../lib/forge-std/src/Test.sol";

// local contracts
import { ArrayUtils } from "../src/libraries/ArrayUtils.sol";

import "./utils/Utility.sol";

contract BasketsManagerTest is Test {
    using ArrayUtils for uint256[];

    uint256[] testArray1 = [8, 7, 4, 6, 9, 2, 10, 1, 3, 5];
    uint256[] testArray2 = [3, 1, 10, 5, 7, 4, 2, 9, 8, 6];

    function test_arrayUtils_insertSort() public {
        assertEq(testArray1.length, testArray2.length);
        assertNotEq(keccak256(abi.encode(testArray1)), keccak256(abi.encode(testArray2)));

        uint256[] memory sorted1 = testArray1.sort();
        uint256[] memory sorted2 = testArray2.sort();

        assertEq(keccak256(abi.encode(sorted1)), keccak256(abi.encode(sorted2)));

        for (uint256 i = testArray1.length; i != 0; ) {
            uint256 expected = i;
            unchecked {
                --i;
            }
            assertEq(sorted1[i], expected);
            assertEq(sorted1[i], sorted2[i]);
        }
    }
}