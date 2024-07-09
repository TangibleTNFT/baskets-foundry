// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

interface IRebaseToken {
    function disableRebase(address account, bool disable) external;
    
    function rebaseIndex() external view returns (uint256 index);
}