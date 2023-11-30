// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "../../lib/forge-std/src/Script.sol";

// local contracts
import { IBasket } from "../../src/interfaces/IBasket.sol";
import { BasketManager } from "../../src/BasketManager.sol";

// helper contracts
import "../../test/utils/MumbaiAddresses.sol";
import "../../test/utils/Utility.sol";

// tangible imports
import { TangibleNFTV2 } from "@tangible/TangibleNFTV2.sol";


/**
 * @title CreateBasketMumbai
 * @author Chase Brown
 * @notice This script allows us to create a new basket from the basket manager on Mumbai.
 */
contract CreateBasketMumbai is Script {

    // ~ Dev Configure ~

    // TODO
    uint256 public constant TOKEN_ID = 9;


    // ~ Script Configure ~

    // mumbai addresses
    BasketManager public basketManager = BasketManager(Mumbai_BasketManager);
    TangibleNFTV2 public realEstateTnft = TangibleNFTV2(Mumbai_TangibleREstateTnft);

    // wallets
    address immutable MUMBAI_DEPLOYER_ADDRESS = vm.envAddress("MUMBAI_DEPLOYER_ADDRESS");
    uint256 immutable MUMBAI_DEPLOYER_PRIVATE_KEY = vm.envUint("MUMBAI_DEPLOYER_PRIVATE_KEY");

    IERC20Metadata public constant MUMBAI_USDC = IERC20Metadata(0x4b64cCe8Af0f1983fb990B152fb2Ff637d26B636);

    uint256 public constant RE_TNFTTYPE = 2;

    address deployerAddress;
    uint256 deployerPrivKey;

    function setUp() public {

        deployerAddress = MUMBAI_DEPLOYER_ADDRESS;
        deployerPrivKey = MUMBAI_DEPLOYER_PRIVATE_KEY;
    }

    function run() public {

        vm.startBroadcast(deployerPrivKey);

        // NOTE: Ensure basketManager is whitelisted on notification dispatcher
        // NOTE: Also ensure basketManager address is set on the Factory

        uint256[] memory features = new uint256[](1);
        features[0] = 1;

        // 1. approve token transfer to basketManager
        realEstateTnft.approve(address(basketManager), TOKEN_ID);

        // 2. Deploy new basket
        (IBasket _basket, uint256[] memory basketShares) = basketManager.deployBasket(
            "Tangible Basket Token ft 1",
            "TBT1",
            RE_TNFTTYPE,
            address(0xe08e7009C2c4ae13C45852876f45913c47eF07Cc), // Note: Mumbai Tangible DAI Mock
            826, // UK_ISO
            features,
            _asSingletonArrayAddress(address(realEstateTnft)),
            _asSingletonArrayUint(TOKEN_ID)
        );

        // log
        console2.log("1. Basket Address:", address(_basket)); // 0x9Df071d66ebaE7cBa85339cFf36D0313c781210E
        console2.log("2. Basket Shares:", basketShares[0]); // 574106000000000000000000

        vm.stopBroadcast();
    }

    // ~ Utility ~

    /// @notice Turns a single uint to an array of uints of size 1.
    function _asSingletonArrayUint(uint256 element) internal pure returns (uint256[] memory) {
        uint256[] memory array = new uint256[](1);
        array[0] = element;

        return array;
    }

    /// @notice Turns a single address to an array of uints of size 1.
    function _asSingletonArrayAddress(address element) internal pure returns (address[] memory) {
        address[] memory array = new address[](1);
        array[0] = element;

        return array;
    }
}
