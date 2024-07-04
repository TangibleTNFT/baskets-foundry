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
 * @title WrappedBasketTokenTest
 * @author Chase Brown
 * @notice This test file contains integration tests for the wrapped baskets token.
 */
contract WrappedBasketTokenTest is Utility {

    // ~ Contracts ~

    // baskets
    Basket public UKRE = Basket(0x835d3E1C0aA079C6164AAd21DCb23E60eb71AF48); // re.al UKRE
    WrappedBasketToken public wUKRE;

    address constant public ACTOR = 0x5111e9bCb01de69aDd95FD31B0f05df51dF946F4;
    address public factoryOwner;

    function setUp() public {
        vm.createSelectFork(REAL_RPC_URL, 74154);
        factoryOwner = IOwnable(Real_FactoryV2).owner();

        // Deploy WrappedBasketToken
        wUKRE = new WrappedBasketToken(
            address(0), // TODO: LZ Endpoint for re.al
            address(UKRE)
        );

        // Deploy proxy for WrappedBasketToken -> initialize
        ERC1967Proxy wUKREProxy = new ERC1967Proxy(
            address(wUKRE),
            abi.encodeWithSelector(WrappedBasketToken.initialize.selector,
                Real_FactoryV2,
                "Wrapped UKRE",
                "wUKRE"
            )
        );
        wUKRE = WrappedBasketToken(address(wUKREProxy));
    }

    // -------
    // Utility
    // -------

    /// @dev local deal to take into account USTB's unique storage layout
    function _deal(address token, address give, uint256 amount) internal {
        // deal doesn't work with USTB since the storage layout is different
        if (token == Real_USTB) {
            // if address is opted out, update normal balance (basket is opted out of rebasing)
            if (give == address(UKRE)) {
                bytes32 USTBStorageLocation = 0x52c63247e1f47db19d5ce0460030c497f067ca4cebf71ba98eeadabe20bace00;
                uint256 mapSlot = 0;
                bytes32 slot = keccak256(abi.encode(give, uint256(USTBStorageLocation) + mapSlot));
                vm.store(Real_USTB, slot, bytes32(amount));
            }
            // else, update shares balance
            else {
                bytes32 USTBStorageLocation = 0x8a0c9d8ec1d9f8b365393c36404b40a33f47675e34246a2e186fbefd5ecd3b00;
                uint256 mapSlot = 2;
                bytes32 slot = keccak256(abi.encode(give, uint256(USTBStorageLocation) + mapSlot));
                vm.store(Real_USTB, slot, bytes32(amount));
            }
        }
        // If not rebase token, use normal deal
        else {
            deal(token, give, amount);
        }
    }

    // ----------
    // Unit Tests
    // ----------

    // ~ deposit ~

    // Deposit X UKRE to get Y wUKRE: X is provided

    /// @dev Verifies proper state changes when WrappedBasketToken::deposit is used when UKRE's rebaseIndex == 1e18.
    function test_wrappedBasketToken_deposit() public {
        // ~ Config ~

        uint256 amount = 100 ether;
        uint256 preBal = UKRE.balanceOf(ACTOR);

        // ~ Pre-state check ~

        assertEq(wUKRE.previewDeposit(amount), amount);
        assertEq(UKRE.balanceOf(address(wUKRE)), 0);
        assertEq(wUKRE.totalSupply(), 0);
        assertEq(wUKRE.balanceOf(address(ACTOR)), 0);

        // ~ Execute deposit ~

        uint256 preview = wUKRE.previewDeposit(amount);

        vm.startPrank(ACTOR);
        UKRE.approve(address(wUKRE), amount);
        assertEq(wUKRE.deposit(amount, ACTOR), preview);
        vm.stopPrank();

        // ~ Post-state check ~

        assertEq(UKRE.balanceOf(ACTOR), preBal - amount);
        assertEq(UKRE.balanceOf(address(wUKRE)), amount);
        assertEq(wUKRE.totalSupply(), amount);
        assertEq(wUKRE.balanceOf(address(ACTOR)), amount);
    }

    /// @dev Verifies proper state changes when WrappedBasketToken::deposit is used when UKRE's rebaseIndex > 1e18.
    function test_wrappedBasketToken_deposit_rebaseIndexNot1() public {
        // ~ Config ~

        // increase rebaseIndex of UKRE
        _deal(Real_USTB, address(UKRE), 10_000 ether);
        vm.prank(UKRE.rebaseIndexManager());
        UKRE.rebase();

        uint256 amount = 100 ether;
        uint256 preBal = UKRE.balanceOf(ACTOR);

        // ~ Pre-state check ~

        assertEq(wUKRE.previewDeposit(amount), amount * 1e18 / UKRE.rebaseIndex());
        assertEq(UKRE.balanceOf(address(wUKRE)), 0);
        assertEq(wUKRE.totalSupply(), 0);
        assertEq(wUKRE.balanceOf(address(ACTOR)), 0);

        // ~ Execute deposit ~

        uint256 preview = wUKRE.previewDeposit(amount);

        vm.startPrank(ACTOR);
        UKRE.approve(address(wUKRE), amount);
        assertApproxEqAbs(wUKRE.deposit(amount, ACTOR), preview, 1);
        vm.stopPrank();

        // ~ Post-state check ~

        assertEq(UKRE.balanceOf(ACTOR), preBal - amount);
        assertApproxEqAbs(UKRE.balanceOf(address(wUKRE)), amount, 1);
        assertApproxEqAbs(wUKRE.totalSupply(), amount * 1e18 / UKRE.rebaseIndex(), 1);
        assertApproxEqAbs(wUKRE.balanceOf(address(ACTOR)), amount * 1e18 / UKRE.rebaseIndex(), 1);
    }

    /// @dev Verifies ZeroAddressException error if argument `receiver` is == address(0)
    function test_wrappedBasketToken_deposit_zeroAddressException() public {
        vm.expectRevert(abi.encodeWithSelector(WrappedBasketToken.ZeroAddressException.selector));
        wUKRE.deposit(1, address(0));
    }

    /// @dev Uses fuzzing to verify proper state changes when WrappedBasketToken::deposit is used when UKRE's rebaseIndex > 1e18.
    function test_wrappedBasketToken_deposit_rebaseIndexNot1_fuzzing(uint256 amount) public {
        // ~ Config ~

        // increase rebaseIndex of UKRE
        _deal(Real_USTB, address(UKRE), 10_000 ether);
        vm.prank(UKRE.rebaseIndexManager());
        UKRE.rebase();

        uint256 preBal = UKRE.balanceOf(ACTOR);
        amount = bound(amount, 1000, preBal);

        // ~ Pre-state check ~

        assertEq(wUKRE.previewDeposit(amount), amount * 1e18 / UKRE.rebaseIndex());
        assertEq(UKRE.balanceOf(address(wUKRE)), 0);
        assertEq(wUKRE.totalSupply(), 0);
        assertEq(wUKRE.balanceOf(address(ACTOR)), 0);

        // ~ Execute deposit ~

        uint256 preview = wUKRE.previewDeposit(amount);

        vm.startPrank(ACTOR);
        UKRE.approve(address(wUKRE), amount);
        assertApproxEqAbs(wUKRE.deposit(amount, ACTOR), preview, 1);
        vm.stopPrank();

        // ~ Post-state check ~

        assertApproxEqAbs(UKRE.balanceOf(ACTOR), preBal - amount, 1);
        assertApproxEqAbs(UKRE.balanceOf(address(wUKRE)), amount, 2);
        assertApproxEqAbs(wUKRE.totalSupply(), amount * 1e18 / UKRE.rebaseIndex(), 2);
        assertApproxEqAbs(wUKRE.balanceOf(address(ACTOR)), amount * 1e18 / UKRE.rebaseIndex(), 2);
    }

    // ~ mint ~

    // Mint X wUKRE using Y UKRE: X is provided

    /// @dev Verifies proper state changes when WrappedBasketToken::mint is used when UKRE's rebaseIndex == 1e18.
    function test_wrappedBasketToken_mint() public {
        // ~ Config ~

        uint256 amount = 100 ether;
        uint256 preBal = UKRE.balanceOf(ACTOR);

        // ~ Pre-state check ~

        assertEq(wUKRE.previewDeposit(amount), amount);
        assertEq(UKRE.balanceOf(address(wUKRE)), 0);
        assertEq(wUKRE.totalSupply(), 0);
        assertEq(wUKRE.balanceOf(address(ACTOR)), 0);

        // ~ Execute deposit ~

        uint256 preview = wUKRE.previewMint(amount);

        vm.startPrank(ACTOR);
        UKRE.approve(address(wUKRE), amount);
        assertEq(wUKRE.mint(amount, ACTOR), preview);
        vm.stopPrank();

        // ~ Post-state check ~

        assertEq(UKRE.balanceOf(ACTOR), preBal - amount);
        assertEq(UKRE.balanceOf(address(wUKRE)), amount);
        assertEq(wUKRE.totalSupply(), amount);
        assertEq(wUKRE.balanceOf(address(ACTOR)), amount);
    }

    /// @dev Verifies ZeroAddressException error if argument `receiver` is == address(0)
    function test_wrappedBasketToken_mint_zeroAddressException() public {
        vm.expectRevert(abi.encodeWithSelector(WrappedBasketToken.ZeroAddressException.selector));
        wUKRE.mint(1, address(0));
    }

    /// @dev Verifies proper state changes when WrappedBasketToken::mint is used when UKRE's rebaseIndex > 1e18.
    function test_wrappedBasketToken_mint_rebaseIndexNot1() public {
        // ~ Config ~

        // increase rebaseIndex of UKRE
        _deal(Real_USTB, address(UKRE), 10_000 ether);
        vm.prank(UKRE.rebaseIndexManager());
        UKRE.rebase();

        uint256 amount = 100 ether;
        uint256 preBal = UKRE.balanceOf(ACTOR);

        uint256 shares = amount * 1e18 / UKRE.rebaseIndex();
        uint256 preview = wUKRE.previewMint(shares);

        // ~ Pre-state check ~

        assertEq(preview, amount);
        assertEq(wUKRE.previewDeposit(amount), shares);
        assertEq(UKRE.balanceOf(address(wUKRE)), 0);
        assertEq(wUKRE.totalSupply(), 0);
        assertEq(wUKRE.balanceOf(address(ACTOR)), 0);

        // ~ Execute deposit ~

        vm.startPrank(ACTOR);
        UKRE.approve(address(wUKRE), amount);
        assertEq(wUKRE.mint(shares, ACTOR), preview);
        vm.stopPrank();

        // ~ Post-state check ~

        assertEq(UKRE.balanceOf(ACTOR), preBal - amount);
        assertApproxEqAbs(UKRE.balanceOf(address(wUKRE)), amount, 1);
        assertApproxEqAbs(wUKRE.totalSupply(), shares, 1);
        assertApproxEqAbs(wUKRE.balanceOf(address(ACTOR)), shares, 1);
    }

    /// @dev Uses fuzzing to verify proper state changes when WrappedBasketToken::mint is used when UKRE's rebaseIndex > 1e18.
    function test_wrappedBasketToken_mint_rebaseIndexNot1_fuzzing(uint256 amount) public {
        // ~ Config ~

        // increase rebaseIndex of UKRE
        _deal(Real_USTB, address(UKRE), 10_000 ether);
        vm.prank(UKRE.rebaseIndexManager());
        UKRE.rebase();

        uint256 preBal = UKRE.balanceOf(ACTOR);
        amount = bound(amount, 1000, preBal);

        uint256 shares = amount * 1e18 / UKRE.rebaseIndex();
        uint256 preview = wUKRE.previewMint(shares);

        // ~ Pre-state check ~

        assertApproxEqAbs(preview, amount, 1);
        assertEq(wUKRE.previewDeposit(amount), shares);
        assertEq(UKRE.balanceOf(address(wUKRE)), 0);
        assertEq(wUKRE.totalSupply(), 0);
        assertEq(wUKRE.balanceOf(address(ACTOR)), 0);

        // ~ Execute deposit ~

        vm.startPrank(ACTOR);
        UKRE.approve(address(wUKRE), amount);
        assertEq(wUKRE.mint(shares, ACTOR), preview);
        vm.stopPrank();

        // ~ Post-state check ~

        assertApproxEqAbs(UKRE.balanceOf(ACTOR), preBal - preview, 2);
        assertApproxEqAbs(UKRE.balanceOf(address(wUKRE)), preview, 2);
        assertApproxEqAbs(wUKRE.totalSupply(), shares, 3);
        assertApproxEqAbs(wUKRE.balanceOf(address(ACTOR)), shares, 3);
    }

    // ~ withdraw ~

    // Withdraw X UKRE from Y wUKRE: X is provided

    /// @dev Verifies proper state changes when WrappedBasketToken::withdraw is used when UKRE's rebaseIndex == 1e18.
    function test_wrappedBasketToken_withdraw() public {
        // ~ Config ~

        uint256 amount = 100 ether;
        uint256 preBal = UKRE.balanceOf(ACTOR);

        vm.startPrank(ACTOR);
        UKRE.approve(address(wUKRE), amount);
        wUKRE.deposit(amount, ACTOR);
        vm.stopPrank();

        // ~ Pre-state check ~

        assertEq(wUKRE.previewWithdraw(amount), amount);
        assertEq(UKRE.balanceOf(ACTOR), preBal - amount);
        assertEq(UKRE.balanceOf(address(wUKRE)), amount);
        assertEq(wUKRE.totalSupply(), amount);
        assertEq(wUKRE.balanceOf(address(ACTOR)), amount);

        // ~ Execute withdraw ~

        uint256 preview = wUKRE.previewWithdraw(amount);

        vm.prank(ACTOR);
        assertEq(wUKRE.withdraw(amount, ACTOR, ACTOR), preview);

        // ~ Post-state check ~

        assertEq(UKRE.balanceOf(ACTOR), preBal);
        assertEq(UKRE.balanceOf(address(wUKRE)), 0);
        assertEq(wUKRE.totalSupply(), 0);
        assertEq(wUKRE.balanceOf(address(ACTOR)), 0);
    }

    /// @dev Verifies proper state changes when WrappedBasketToken::withdraw is used when UKRE's rebaseIndex > 1e18.
    function test_wrappedBasketToken_withdraw_rebaseIndexNot1() public {
        // ~ Config ~

        // increase rebaseIndex of UKRE
        _deal(Real_USTB, address(UKRE), 10_000 ether);
        vm.prank(UKRE.rebaseIndexManager());
        UKRE.rebase();

        uint256 amount = 100 ether;
        uint256 preBal = UKRE.balanceOf(ACTOR);

        uint256 wrappedAmount = wUKRE.previewDeposit(amount);

        vm.startPrank(ACTOR);
        UKRE.approve(address(wUKRE), amount);
        wUKRE.deposit(amount, ACTOR);
        vm.stopPrank();

        // ~ Pre-state check ~

        assertEq(UKRE.balanceOf(ACTOR), preBal - amount);
        assertApproxEqAbs(UKRE.balanceOf(address(wUKRE)), amount, 1);
        assertApproxEqAbs(wUKRE.totalSupply(), wrappedAmount, 1);
        assertApproxEqAbs(wUKRE.balanceOf(address(ACTOR)), wrappedAmount, 1);
        
        wrappedAmount = wUKRE.balanceOf(address(ACTOR));

        // ~ Execute withdraw ~

        uint256 preview = wUKRE.previewWithdraw(amount-1);

        vm.prank(ACTOR);
        assertEq(wUKRE.withdraw(amount-1, ACTOR, ACTOR), preview);

        // ~ Post-state check ~

        assertApproxEqAbs(UKRE.balanceOf(ACTOR), preBal, 2);
        assertApproxEqAbs(UKRE.balanceOf(address(wUKRE)), 0, 2);
        assertApproxEqAbs(wUKRE.totalSupply(), 0, 2);
        assertApproxEqAbs(wUKRE.balanceOf(address(ACTOR)), 0, 2);
    }

    /// @dev Verifies ZeroAddressException error if argument `receiver` is == address(0)
    function test_wrappedBasketToken_withdraw_zeroAddressException() public {
        // receiver cannot be address(0)
        vm.expectRevert(abi.encodeWithSelector(WrappedBasketToken.ZeroAddressException.selector));
        wUKRE.withdraw(1, address(0), ACTOR);

        // owner cannot be address(0)
        vm.expectRevert(abi.encodeWithSelector(WrappedBasketToken.ZeroAddressException.selector));
        wUKRE.withdraw(1, ACTOR, address(0));
    }

    // ~ redeem ~

    // Redeem X wUKRE for Y UKRE: X is provided

    /// @dev Verifies proper state changes when WrappedBasketToken::redeem is used when UKRE's rebaseIndex == 1e18.
    function test_wrappedBasketToken_redeem() public {
        // ~ Config ~

        uint256 amount = 100 ether;
        uint256 preBal = UKRE.balanceOf(ACTOR);

        vm.startPrank(ACTOR);
        UKRE.approve(address(wUKRE), amount);
        wUKRE.deposit(amount, ACTOR);
        vm.stopPrank();

        // ~ Pre-state check ~

        assertEq(wUKRE.previewWithdraw(amount), amount);
        assertEq(UKRE.balanceOf(ACTOR), preBal - amount);
        assertEq(UKRE.balanceOf(address(wUKRE)), amount);
        assertEq(wUKRE.totalSupply(), amount);
        assertEq(wUKRE.balanceOf(address(ACTOR)), amount);

        // ~ Execute withdraw ~

        uint256 preview = wUKRE.previewRedeem(amount);

        vm.prank(ACTOR);
        assertEq(wUKRE.redeem(amount, ACTOR, ACTOR), preview);

        // ~ Post-state check ~

        assertEq(UKRE.balanceOf(ACTOR), preBal);
        assertEq(UKRE.balanceOf(address(wUKRE)), 0);
        assertEq(wUKRE.totalSupply(), 0);
        assertEq(wUKRE.balanceOf(address(ACTOR)), 0);
    }

    /// @dev Verifies proper state changes when WrappedBasketToken::redeem is used when UKRE's rebaseIndex > 1e18.
    function test_wrappedBasketToken_redeem_rebaseIndexNot1() public {
        // ~ Config ~

        // increase rebaseIndex of UKRE
        _deal(Real_USTB, address(UKRE), 10_000 ether);
        vm.prank(UKRE.rebaseIndexManager());
        UKRE.rebase();

        uint256 amount = 100 ether;
        uint256 preBal = UKRE.balanceOf(ACTOR);

        uint256 wrappedAmount = wUKRE.previewDeposit(amount);

        vm.startPrank(ACTOR);
        UKRE.approve(address(wUKRE), amount);
        wUKRE.deposit(amount, ACTOR);
        vm.stopPrank();

        // ~ Pre-state check ~

        assertApproxEqAbs(UKRE.balanceOf(ACTOR), preBal - amount, 1);
        assertApproxEqAbs(UKRE.balanceOf(address(wUKRE)), amount, 2);
        assertApproxEqAbs(wUKRE.totalSupply(), wrappedAmount, 1);
        assertApproxEqAbs(wUKRE.balanceOf(address(ACTOR)), wrappedAmount, 1);
        
        wrappedAmount = wUKRE.balanceOf(address(ACTOR));

        // ~ Execute withdraw ~

        uint256 preview = wUKRE.previewRedeem(wrappedAmount);

        vm.prank(ACTOR);
        assertEq(wUKRE.redeem(wrappedAmount, ACTOR, ACTOR), preview);

        // ~ Post-state check ~

        assertApproxEqAbs(UKRE.balanceOf(ACTOR), preBal, 3);
        assertApproxEqAbs(UKRE.balanceOf(address(wUKRE)), 0, 3);
        assertApproxEqAbs(wUKRE.totalSupply(), 0 ,0);
        assertApproxEqAbs(wUKRE.balanceOf(address(ACTOR)), 0, 0);
    }

    /// @dev Verifies ZeroAddressException error if argument `receiver` is == address(0)
    function test_wrappedBasketToken_redeem_zeroAddressException() public {
        // receiver cannot be address(0)
        vm.expectRevert(abi.encodeWithSelector(WrappedBasketToken.ZeroAddressException.selector));
        wUKRE.redeem(1, address(0), ACTOR);

        // owner cannot be address(0)
        vm.expectRevert(abi.encodeWithSelector(WrappedBasketToken.ZeroAddressException.selector));
        wUKRE.redeem(1, ACTOR, address(0));
    }

    /// @dev Uses fuzzing to verify proper state changes when WrappedBasketToken::redeem is used when UKRE's rebaseIndex > 1e18.
    function test_wrappedBasketToken_redeem_rebaseIndexNot1_fuzzing(uint256 amount) public {
        // ~ Config ~

        // increase rebaseIndex of UKRE
        _deal(Real_USTB, address(UKRE), 10_000 ether);
        vm.prank(UKRE.rebaseIndexManager());
        UKRE.rebase();

        uint256 preBal = UKRE.balanceOf(ACTOR);
        amount = bound(amount, 1000, preBal);

        uint256 wrappedAmount = wUKRE.previewDeposit(amount);

        vm.startPrank(ACTOR);
        UKRE.approve(address(wUKRE), amount);
        wUKRE.deposit(amount, ACTOR);
        vm.stopPrank();

        // ~ Pre-state check ~

        assertApproxEqAbs(UKRE.balanceOf(ACTOR), preBal - amount, 1);
        assertApproxEqAbs(UKRE.balanceOf(address(wUKRE)), amount, 2);
        assertApproxEqAbs(wUKRE.totalSupply(), wrappedAmount, 1);
        assertApproxEqAbs(wUKRE.balanceOf(address(ACTOR)), wrappedAmount, 1);
        
        wrappedAmount = wUKRE.balanceOf(address(ACTOR));

        // ~ Execute withdraw ~

        uint256 preview = wUKRE.previewRedeem(wrappedAmount);

        vm.prank(ACTOR);
        assertEq(wUKRE.redeem(wrappedAmount, ACTOR, ACTOR), preview);

        // ~ Post-state check ~

        assertApproxEqAbs(UKRE.balanceOf(ACTOR), preBal, 3);
        assertApproxEqAbs(UKRE.balanceOf(address(wUKRE)), 0, 3);
        assertApproxEqAbs(wUKRE.totalSupply(), 0 ,0);
        assertApproxEqAbs(wUKRE.balanceOf(address(ACTOR)), 0, 0);
    }
}