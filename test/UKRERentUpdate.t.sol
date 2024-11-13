// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "../lib/forge-std/src/Test.sol";
import { StdInvariant } from "../lib/forge-std/src/StdInvariant.sol";

// chainlink interface imports
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// oz imports
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Utils, ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

// tangible contract
import { FactoryV2 } from "@tangible/FactoryV2.sol";
import { TangibleNFTV2 } from "@tangible/TangibleNFTV2.sol";
import { RentManagerDeployer } from "@tangible/RentManagerDeployer.sol";
import { RealtyOracleTangibleV2 } from "@tangible/priceOracles/RealtyOracleV2.sol";
import { TNFTMarketplaceV2 } from "@tangible/MarketplaceV2.sol";
import { TangiblePriceManagerV2 } from "@tangible/TangiblePriceManagerV2.sol";
import { CurrencyFeedV2 } from "@tangible/helpers/CurrencyFeedV2.sol";
import { TNFTMetadata } from "@tangible/TNFTMetadata.sol";
import { RentManager } from "@tangible/RentManager.sol";
import { RWAPriceNotificationDispatcher } from "@tangible/notifications/RWAPriceNotificationDispatcher.sol";
import { MockMatrixOracle } from "@tangible/tests/mocks/MockMatrixOracle.sol";

// tangible interface imports
import { IVoucher } from "@tangible/interfaces/IVoucher.sol";
import { IFactory } from "@tangible/interfaces/IFactory.sol";
import { IOwnable } from "@tangible/interfaces/IOwnable.sol";
import { ITangibleNFT } from "@tangible/interfaces/ITangibleNFT.sol";

// local contracts
import { Basket } from "../src/Basket.sol";
import { CurrencyCalculator } from "../src/CurrencyCalculator.sol";
import { IBasket } from "../src/interfaces/IBasket.sol";
import { BasketManager } from "../src/BasketManager.sol";
import { BasketsVrfConsumer } from "../src/BasketsVrfConsumer.sol";
import { IGetNotificationDispatcher } from "../src/interfaces/IGetNotificationDispatcher.sol";
import { IUSTB } from "../src/interfaces/IUSTB.sol";

// local helper contracts
import "./utils/UnrealAddresses.sol";
import "./utils/Utility.sol";


/**
 * @title BasketsRentUpdateTest
 * @author Chase Brown
 * @notice This test file contains integration tests simulating the update in rent token that the production UKRE
 * is anticipated to undergo.
 */
contract BasketsRentUpdateTest is Utility {

    // ~ Contracts ~

    // baskets
    Basket public constant UKRE = Basket(0x835d3E1C0aA079C6164AAd21DCb23E60eb71AF48);
    BasketManager public constant basketManager = BasketManager(0x5e581ce0472bF528E7F5FCB96138d7759AC2ac3f);

    //CurrencyCalculator public currencyCalculator;
    //BasketsVrfConsumer public basketVrfConsumer;

    // tangible unreal contracts
    FactoryV2 public constant factoryV2 = FactoryV2(0x6DD9abb56CeCbC6FCB27a716bBECd1eFDfE09f5F);
    RentManagerDeployer public constant rentManagerDeployer = RentManagerDeployer(0x0cC6afE54AFa1AeF0Ec94CC8471859812C54D8De);
    TangibleNFTV2 public constant realEstateTnft = TangibleNFTV2(0x03634A8Aea4Ca702c0Af7b1480c5015e5BbF3cb9);
    // RealtyOracleTangibleV2 public realEstateOracle = RealtyOracleTangibleV2(Unreal_RealtyOracleTangibleV2);
    // MockMatrixOracle public chainlinkRWAOracle = MockMatrixOracle(Unreal_MockMatrix);
    // TNFTMarketplaceV2 public marketplace = TNFTMarketplaceV2(Unreal_Marketplace);
    // TangiblePriceManagerV2 public priceManager = TangiblePriceManagerV2(Unreal_PriceManager);
    // CurrencyFeedV2 public currencyFeed = CurrencyFeedV2(Unreal_CurrencyFeedV2);
    // TNFTMetadata public metadata = TNFTMetadata(Unreal_TNFTMetadata);
    RentManager public rentManager = RentManager(0xDbDa59243973e9147f7b064921a238bbdEc8f4D3);
    // RWAPriceNotificationDispatcher public notificationDispatcher = RWAPriceNotificationDispatcher(Unreal_RWAPriceNotificationDispatcher);

    // ~ Actors and Variables ~

    uint256 public preTotalValue;

    address public FACTORY_OWNER;
    address public ORACLE_OWNER = 0xf7032d3874557fAF9D9E861E5027300ABA1f0026;
    //address public TANGIBLE_LABS; // NOTE: category owner

    address public constant MULTISIG = 0x5111e9bCb01de69aDd95FD31B0f05df51dF946F4;
    address public constant DEPOSITOR = 0x55dBd594F19f7bE69eaC7910bD4E782D1F417820;

    address public constant USTB = 0x83feDBc0B85c6e29B589aA6BdefB1Cc581935ECD;
    address public constant USDC = 0xc518A88c67CECA8B3f24c4562CB71deeB2AF86B7;

    /// @notice Config function for test cases.
    function setUp() public {
        vm.createSelectFork(REAL_RPC_URL, 799701); // fork - re.al block 766184 @ Oct 9th 2024 11:25:17 AM (-07:00 UTC)

        FACTORY_OWNER = IOwnable(address(factoryV2)).owner();

        vm.startPrank(FACTORY_OWNER);
        basketManager.updateBasketImplementation(address(new Basket()));
        vm.stopPrank();

        // new category owner
        //TANGIBLE_LABS = factoryV2.categoryOwner(ITangibleNFT(address(realEstateTnft)));

        // Claim all claimable USTB from RentManager
        IBasket.TokenData[] memory tokens = UKRE.getDepositedTnfts();
        for (uint256 i; i < tokens.length; ++i) {
            uint256 tokenId = tokens[i].tokenId;
            uint256 claimable = rentManager.claimableRentForToken(tokenId);
            if (claimable != 0) {
                vm.prank(FACTORY_OWNER);
                UKRE.claimRentForToken(address(realEstateTnft), tokenId);
                assertEq(rentManager.claimableRentForToken(tokenId), 0);
            }
        }

        // Rebase
        vm.prank(UKRE.rebaseIndexManager());
        UKRE.rebase();

        preTotalValue = UKRE.getTotalValueOfBasket();

        // USTB rent bal -> 6,897.166324322916666825
        // USDC rent bal needed (atleast) -> 6,897.166325 TODO: Verify

        // remove USTB from UKRE 
        vm.prank(FACTORY_OWNER);
        UKRE.setWithdrawRole(FACTORY_OWNER, true);
        uint256 amountRent = UKRE.getRentBal();
        uint256 preBal = IERC20(USTB).balanceOf(FACTORY_OWNER);
        assertEq(IERC20(USTB).balanceOf(address(UKRE)), amountRent);
        vm.prank(FACTORY_OWNER);
        UKRE.withdrawRent(amountRent);
        assertEq(IERC20(USTB).balanceOf(FACTORY_OWNER), preBal + amountRent);

        emit log_named_uint("pre total value", preTotalValue);
        emit log_named_uint("rent balance", UKRE.getRentBal()); // 1
        emit log_named_uint("total value", UKRE.getTotalValueOfBasket()); // 1,268,600.918732800000000000
        emit log_named_uint("rebaseIndex", UKRE.rebaseIndex()); // 1.016579219834246468

        // calculate amount of new rent in USDC (subtracting 12 decimals)
        uint256 amountNewRent = amountRent / 10**12 + 1;
        emit log_named_uint("USDC amount", amountNewRent);

        // change rent token on UKRE
        vm.prank(FACTORY_OWNER);
        UKRE.updatePrimaryRentToken(USDC, false);

        // deposit new rent amount of USDC
        deal(USDC, FACTORY_OWNER, amountNewRent);
        vm.startPrank(FACTORY_OWNER);
        IERC20(USDC).approve(address(UKRE), amountNewRent);
        UKRE.depositRent(amountNewRent);
        vm.stopPrank();

        // rebase
        vm.prank(UKRE.rebaseIndexManager());
        UKRE.rebase();

        // update rent token on BasketManager
        vm.prank(FACTORY_OWNER);
        basketManager.updatePrimaryRentToken(USDC, false);

        // deposit new rent as USDC via RentManager
        // TODO ** This can be a test. We only need USDC in the contract balance to test rebase.

        _createLabels();
        _updateRentManager();
    }


    // -------
    // Utility
    // -------

    /// @notice Creates labels for addresses. Makes traces easier to read.
    function _createLabels() internal override {
        vm.label(address(this), "TEST_FILE");
        //vm.label(TANGIBLE_LABS, "TANGIBLE_LABS");
        // TODO
        super._createLabels();
    }

    // function _overwriteRentManagerOnFactory(address newRentManager) internal {
    //     assertNotEq(address(factoryV2.rentManager(realEstateTnft)), newRentManager);

    //     bytes32 USTBStorageLocation = 0x8a0c9d8ec1d9f8b365393c36404b40a33f47675e34246a2e186fbefd5ecd3b00;
    //     uint256 mapSlot = 18;
    //     bytes32 slot = keccak256(abi.encode(address(realEstateTnft), mapSlot));
    //     vm.store(address(factoryV2), slot, bytes32(abi.encodePacked(newRentManager)));

    //     assertEq(address(factoryV2.rentManager(realEstateTnft)), newRentManager);
    // }

    function _updateRentManager() internal returns (address) {
        // // deploy new rentManager
        // vm.prank(address(factoryV2));
        // address newRentManager = address(rentManagerDeployer.deployRentManager(address(realEstateTnft)));
        // // update address on factory
        // _overwriteRentManagerOnFactory(newRentManager);
    }

    /// @dev Utility method for grabbing a RE TNFT from the multisig.
    function _stealTokenFromMultisig(address recipient, uint256 tokenId) internal {
        vm.prank(MULTISIG);
        realEstateTnft.transferFrom(MULTISIG, recipient, tokenId);
    }

    function _depositRent(uint256 tokenId, uint256 amount) internal {
        deal(USDC, DEPOSITOR, amount);
        vm.startPrank(DEPOSITOR);
        IERC20(USDC).approve(address(rentManager), amount);
        rentManager.deposit(
            tokenId,
            USDC,
            amount,
            0,
            block.timestamp + 1,
            true
        );
        vm.stopPrank();
        vm.warp(block.timestamp + 1);
    }


    // ----------
    // Unit Tests
    // ----------

    /// @dev Verifies UKRE::getRentBal returns the amount of USDC in the basket balance.
    function test_rentUpdate_getRentBal() public {
        assertEq(UKRE.getRentBal(), IERC20(USDC).balanceOf(address(UKRE)));
    }

    /// @dev Verifies the new total value of the basket is the same as before the token switch from USTB to USDC.
    /// Obviously, we take into account the 12 decimal difference.
    function test_rentUpdate_getTotalValueOfBasket() public {
        // 1,275,498.085057122916666825 (pre-withdraw of USTB) -> preTotalValue
        // 1,268,600.918732800000000000 (post-withdraw of USTB || pre-deposit of USDC)
        // 1,275,498.085057800000000000 (post-deposit of USDC)

        assertApproxEqAbs(UKRE.getTotalValueOfBasket(), preTotalValue, 1 * 10**12);
    }

    /// @dev Verfieis UKRE::decimalsDiff returns the proper precision difference between 
    /// UKRE::decimals & USDC::decimals.
    function test_rentUpdate_decimalsDiff() public {
        assertEq(UKRE.decimalsDiff(), 10 ** 12);
    }

    /// @dev Verfies proper state changes when UKRE::withdrawRent is executed.
    function test_rentUpdate_withdrawRent() public {

        uint256 amount = 100 * 10**6;

        uint256 preBalBasket = IERC20(USDC).balanceOf(address(UKRE));
        uint256 preBalOwner = IERC20(USDC).balanceOf(FACTORY_OWNER);
        uint256 preTotalRentValue = UKRE.totalRentValue();

        vm.prank(FACTORY_OWNER);
        UKRE.withdrawRent(amount);

        // ~ State-check ~

        assertEq(IERC20(USDC).balanceOf(address(UKRE)), preBalBasket - amount);
        assertEq(IERC20(USDC).balanceOf(FACTORY_OWNER), preBalOwner + amount);
        assertEq(UKRE.totalRentValue(), preTotalRentValue - amount);
    }

    /// @dev Verifies proper state changes in the basket when a deposit occurs
    /// with a token that has unclaimed USDC rewards.
    function test_rentUpdate_deposit() public {
        // ~ Config ~

        uint256 tokenId = 210;
        uint256 amountRent = 100 * 1e6;

        _stealTokenFromMultisig(JOE, tokenId);
        _depositRent(tokenId, amountRent);

        // ~ Pre-state check ~

        assertEq(rentManager.claimableRentForToken(tokenId), amountRent);
        uint256 preBal = IERC20(USDC).balanceOf(JOE);

        // ~ Execute deposit ~

        vm.startPrank(JOE);
        realEstateTnft.approve(address(UKRE), tokenId);
        UKRE.depositTNFT(address(realEstateTnft), tokenId);
        vm.stopPrank();

        // ~ Post-state check ~

        assertEq(rentManager.claimableRentForToken(tokenId), 0);
        assertEq(IERC20(USDC).balanceOf(JOE), amountRent + preBal);
    }
}