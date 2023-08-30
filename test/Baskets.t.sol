// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "../lib/forge-std/src/Test.sol";
import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';

import { Basket } from "../src/Baskets.sol";
import { BasketDeployer } from "../src/BasketsDeployer.sol";

// https://docs.chain.link/data-feeds/price-feeds/addresses/?network=polygon#Polygon%20Mainnet
// Polygon GBP / USD Price Feed: 0x099a2540848573e94fb1Ca0Fa420b00acbBc845a
// polygon USDC / USD Price Feed: 0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7

contract BasketsTest is Test {
    Basket public basket;
    BasketDeployer public basketDeployer;

    function setUp() public {

        // Deploy basket
        basket = new Basket(
            "Tangible Basket Token",
            "TBT",
            address(222), // TODO: Change to addressProvider
            1, // tnftType
            address(333) // TODO: Change to currencyFeed
        );
        
    }

}
