// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {TokenPair} from "../src/contracts/TokenPair.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract TokenPairTest is Test {
    TokenPair public pair;
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;

    address internal lp = makeAddr("lp");
    address internal trader = makeAddr("trader");

    uint256 internal constant MINIMUM_LIQUIDITY = 1_000;

    event Transfer(address indexed from, address indexed to, uint256 value);
    // Pair events
    event Mint(address indexed sender, uint256 amountA, uint256 amountB);
    event Burn(address indexed sender, uint256 amountA, uint256 amountB, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amountAIn,
        uint256 amountBIn,
        uint256 amountAOut,
        uint256 amountBOut,
        address indexed to
    );
    event Sync(uint256 reserveA, uint256 reserveB);

    function setUp() public {
        uint8 decimals = 18;
        tokenA = new MockERC20("TokenA", "TKA", decimals);
        tokenB = new MockERC20("TokenB", "TKB", decimals);

        pair = new TokenPair();
        pair.initialize(address(tokenA), address(tokenB));
    }

    function testInitializeAndSetsMetadataAndFactory() public view {
        assertEq(pair.name(), "LP Token");
        assertEq(pair.symbol(), "LPT");
        assertEq(pair.factory(), address(this));
    }

    function testGetReservesInitiallyZero() public view {
        (uint256 rA, uint256 rB, uint256 ts) = pair.getReserves();
        assertEq(rA, 0);
        assertEq(rB, 0);
        assertEq(ts, 0);
    }

    function testInitializeRevertsWhenNotFactory() public {
        vm.prank(makeAddr("notFactory"));
        vm.expectRevert(bytes("Not Factory"));
        pair.initialize(address(tokenA), address(tokenB));
    }

    function testMintAddingLiquidityForTheFirstTime() public {
        //sqrt(1e18 * 4e18) = 2e18
        uint256 amountA = 1e18;
        uint256 amountB = 4e18;

        uint256 expectedTotalSupply = 2e18;

        uint256 expectedLpToProvider = expectedTotalSupply - MINIMUM_LIQUIDITY;

        tokenA.mint(lp, amountA);
        tokenB.mint(lp, amountB);

        vm.startPrank(lp);
        tokenA.transfer(address(pair), amountA);
        tokenB.transfer(address(pair), amountB);

        vm.expectEmit(true, true, false, true, address(pair));
        emit Transfer(address(0), address(0xdead), MINIMUM_LIQUIDITY);

        vm.expectEmit(true, true, true, true, address(pair));
        emit Transfer(address(0), lp, expectedLpToProvider);

        vm.expectEmit(false, false, false, true, address(pair));
        emit Sync(amountA, amountB);

        vm.expectEmit(true, false, false, true, address(pair));
        emit Mint(lp, amountA, amountB);

        uint256 liquidity = pair.mint(lp);
        vm.stopPrank();

        assertEq(liquidity, expectedLpToProvider);
        assertEq(pair.totalSupply(), expectedTotalSupply);
        assertEq(pair.balanceOf(lp), expectedLpToProvider);
        assertEq(tokenA.balanceOf(address(pair)), amountA);
        assertEq(tokenB.balanceOf(address(pair)), amountB);

        (uint256 rA, uint256 rB,) = pair.getReserves();
        assertEq(rA, amountA);
        assertEq(rB, amountB);
    }

    function addLiquidity(uint256 amountA, uint256 amountB, address provider) internal {
        tokenA.mint(provider, amountA);
        tokenB.mint(provider, amountB);

        vm.startPrank(provider);
        tokenA.transfer(address(pair), amountA);
        tokenB.transfer(address(pair), amountB);
        pair.mint(provider);
        vm.stopPrank();
    }

    function testBurnForAddedLiquidity() public {
        uint256 amountA = 3e18;
        uint256 amountB = 3e18;

        addLiquidity(amountA, amountB, lp);

        uint256 expectedTotalSupply = 3e18;
        uint256 burnLiquidity = expectedTotalSupply - MINIMUM_LIQUIDITY;

        vm.startPrank(lp);
        pair.transfer(address(pair), burnLiquidity);

        vm.expectEmit(true, true, true, true, address(pair));
        emit Transfer(address(pair), address(0), burnLiquidity);

        vm.expectEmit(false, false, false, true, address(pair));
        emit Sync(MINIMUM_LIQUIDITY, MINIMUM_LIQUIDITY);

        vm.expectEmit(true, false, false, true, address(pair));
        emit Burn(lp, amountA - MINIMUM_LIQUIDITY, amountB - MINIMUM_LIQUIDITY, lp);

        (uint256 outA, uint256 outB) = pair.burn(lp);
        vm.stopPrank();

        assertEq(outA, amountA - MINIMUM_LIQUIDITY);
        assertEq(outB, amountB - MINIMUM_LIQUIDITY);

        assertEq(pair.balanceOf(lp), 0);
        assertEq(pair.totalSupply(), MINIMUM_LIQUIDITY);

        assertEq(tokenA.balanceOf(address(pair)), MINIMUM_LIQUIDITY);
        assertEq(tokenB.balanceOf(address(pair)), MINIMUM_LIQUIDITY);

        (uint256 rA, uint256 rB,) = pair.getReserves();
        assertEq(rA, MINIMUM_LIQUIDITY);
        assertEq(rB, MINIMUM_LIQUIDITY);
    }

    function testSwapTokenAInTokenBOut() public {
        //Each row: [amountIn,reserveA,resreveB]
        uint256[3][] memory cases = new uint256[3][](4);
        cases[0] = [uint256(1e18), uint256(5e18), uint256(10e18)];
        cases[1] = [uint256(2e18), uint256(5e18), uint256(10e18)];
        cases[2] = [uint256(1e18), uint256(10e18), uint256(5e18)];
        cases[3] = [uint256(1e18), uint256(100e18), uint256(100e18)];

        for (uint256 i = 0; i < cases.length; i++) {
            setUp();
            uint256 amountIn = cases[i][0];
            uint256 reserveA = cases[i][1];
            uint256 reserveB = cases[i][2];

            addLiquidity(reserveA, reserveB, lp);

            uint256 amountOut = _getAmountOutAtoB(amountIn, reserveA, reserveB);
            assertTrue(amountOut > 0);
            assertTrue(amountOut < reserveB);

            tokenA.mint(trader, amountIn);
            vm.startPrank(trader);
            tokenA.transfer(address(pair), amountIn);

            vm.expectRevert(bytes("INSUFFICIENT_LIQUIDITY"));
            pair.swap(0, amountOut + 1, trader);

            pair.swap(0, amountOut, trader);
            vm.stopPrank();

            (uint256 rA, uint256 rB,) = pair.getReserves();
            assertEq(rA, reserveA + amountIn);
            assertEq(rB, reserveB - amountOut);
            assertEq(tokenA.balanceOf(address(pair)), reserveA + amountIn);
            assertEq(tokenB.balanceOf(address(pair)), reserveB - amountOut);
        }
    }

    function _getAmountOutAtoB(uint256 amountIn, uint256 reserveA, uint256 reserveB) internal pure returns (uint256) {
        uint256 amountInWithFee = amountIn * 998;
        uint256 numerator = amountInWithFee * reserveB;
        uint256 denominator = (reserveA * 1000) + amountInWithFee;
        return numerator / denominator;
    }

    function testSwapevertsOnInvalidOutputAndAddresses() public {
        addLiquidity(5e18, 10e18, lp);

        // both outputs zero
        vm.expectRevert(bytes("INVALID_OUTPUT_AMOUNT"));
        pair.swap(0, 0, trader);

        // output >= reserve
        (uint256 rA, uint256 rB,) = pair.getReserves();

        vm.expectRevert(bytes("INSUFFICIENT_RESERVE"));
        pair.swap(0, rB, trader);
        vm.expectRevert(bytes("INSUFFICIENT_RESERVE"));
        pair.swap(rA, 0, trader);

        // invalid output address
        vm.expectRevert(bytes("INVALID_OUTPUT_ADDRESS"));
        pair.swap(0, 1, address(tokenB));

        vm.expectRevert(bytes("INVALID_OUTPUT_ADDRESS"));
        pair.swap(1, 0, address(tokenA));
    }

    function testSwapRevertsWhenNoInputProvided() public {
        addLiquidity(5e18, 10e18, lp);

        // try to take output without transferring input first
        vm.expectRevert(bytes("INSUFFICIENT_INPUT_AMOUNT"));
        pair.swap(0, 1, trader);
    }
}
