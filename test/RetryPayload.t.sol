// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "../lib/forge-std/src/Test.sol";
import { StdInvariant } from "../lib/forge-std/src/StdInvariant.sol";

// oz imports
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Utils, ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { IOwnable } from "@tangible/interfaces/IOwnable.sol";

// local contracts
import { Basket } from "../src/Basket.sol";
import { WrappedBasketToken } from "../src/wrapped/WrappedBasketToken.sol";

// local helper contracts
import "./utils/Re.alAddresses.sol";
import "./utils/Utility.sol";


/**
 * @title RetryPayloaTest
 * @author Chase Brown
 * @notice This test file contains integration tests for the wrapped baskets token.
 */
contract RetryPayloaTest is Utility {

    // ~ Contracts ~

    // baskets
    WrappedBasketToken wUKRE = WrappedBasketToken(0x2e8b62a34F47dB4D1e82bb1D811522A59A61db73);

    function setUp() public {
        vm.createSelectFork("https://1rpc.io/sepolia");
    }

    function test_retryPayload() public {
        // vm.prank(0xae92d5aD7583AD66E49A0c67BAd18F6ba52dDDc1);
        // wUKRE.lzReceive(
        //     10262, 
        //     abi.encodePacked(0x2e8b62a34F47dB4D1e82bb1D811522A59A61db73, 0x2e8b62a34F47dB4D1e82bb1D811522A59A61db73),
        //     1,
        //     hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000dda9b8d3dd930510000000000000000000000000000000000000000000000000000000000000014057690d27577ce963d682c502ae23fe936cd5c7e000000000000000000000000"
        // );
        // bytes memory addy = abi.encodePacked(0x2e8b62a34F47dB4D1e82bb1D811522A59A61db73, 0x2e8b62a34F47dB4D1e82bb1D811522A59A61db73);
        // emit log_bytes(addy);
        vm.prank(0x0Cfd2CDc46fDDD3c6f08B75c510E689D61441aF6);
        wUKRE.retryMessage(
            10262, 
            hex"2e8b62a34f47db4d1e82bb1d811522a59a61db732e8b62a34f47db4d1e82bb1d811522a59a61db73",
            1,
            hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000dda9b8d3dd930510000000000000000000000000000000000000000000000000000000000000014057690d27577ce963d682c502ae23fe936cd5c7e000000000000000000000000"
        );
    }
}