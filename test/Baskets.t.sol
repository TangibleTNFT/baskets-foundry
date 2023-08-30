// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "../lib/forge-std/src/Test.sol";
import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';

import { Basket } from "../src/Baskets.sol";
import { BasketDeployer } from "../src/BasketsDeployer.sol";

contract BasketsTest is Test {
    Basket public basket;
    BasketDeployer public basketDeployer;

    function setUp() public {

        // Deploy basket
        basket = new Basket("Tangible Basket Token", "TBT");
        
    }

}
