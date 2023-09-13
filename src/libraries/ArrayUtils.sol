// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

/**
 * @title ArrayUtils Library
 * @author Caesar LaVey
 * @notice Provides utility functions to sort uint256 arrays.
 */
library ArrayUtils {

    /**
     * @notice Sorts an array of uint256 numbers in ascending order.
     * @dev Uses insertion sort algorithm for sorting.
     * @param arr The array of uint256 numbers to be sorted.
     * @return sortedArr The sorted array. 
     */
    function sort(uint256[] memory arr) internal pure returns (uint256[] memory) {
        for (uint256 i = 1; i < arr.length; ) {
            uint256 key = arr[i];
            uint256 j = i - 1;

            // Loop to find the correct position for the element.
            while (j != type(uint256).max && arr[j] > key) {
                arr[j + 1] = arr[j];
                unchecked {
                    --j;
                }
            }

            unchecked {
                arr[j + 1] = key;
                ++i;
            }
        }

        return arr;
    }
}