// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AMMRouter} from "src/contracts/AMMRouter.sol";
import {AMMLibrary} from "src/libraries/AMMLibrary.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {PairFactory} from "src/contracts/PairFactory.sol";
import {TokenPair} from "src/contracts/TokenPair.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract AMMRouterTest is Test {

    MockERC20 tokenA;
    MockERC20 tokenB;
    PairFactory pairFactory;
    AMMRouter ammRouter;
    address internal lp = makeAddr("lp");

    uint256 internal constant MINIMUM_LIQUIDITY = 1_000;
    uint256 internal constant DEFAULT_DEADLINE_OFFSET = 1 hours;

    function _validDeadline() internal view returns (uint256) {
        return block.timestamp + DEFAULT_DEADLINE_OFFSET;
    }

    function _invalidDeadline() internal view returns (uint256) {
        return block.timestamp - 1;
    }

    function setUp() public {
        tokenA = new MockERC20("TokenA","TKA",18);
        tokenB = new MockERC20("TokenB","TKA",18);
        pairFactory = new PairFactory();
        ammRouter = new AMMRouter(address(pairFactory));
    }

    function testConstructor() public {
      assertEq(ammRouter.factory(),address(pairFactory));
      address expectedPair = pairFactory.createPair(
        address(tokenA),
        address(tokenB)
      );
      (,,address calculatedPair) = ammRouter.getReserves(
        address(tokenA),
        address(tokenB)
      );
      assertEq(calculatedPair,expectedPair,"Pair address calculation should match");
    }

  function testGetReservesWithoutCreatingPair() public view {
        (
            uint256 reserveA_fromAB,
            uint256 reserveB_fromAB,
            address pair_fromAB
        ) = ammRouter.getReserves(address(tokenA), address(tokenB));
        (
            uint256 reserveB_fromBA,
            uint256 reserveA_fromBA,
            address pair_fromBA
        ) = ammRouter.getReserves(address(tokenB), address(tokenA));

        assertEq(reserveA_fromAB, 0);
        assertEq(reserveB_fromAB, 0);
        assertEq(reserveA_fromBA, 0);
        assertEq(reserveB_fromBA, 0);

        address expectedPair = AMMLibrary.pairFor(
            address(pairFactory),
            address(tokenA),
            address(tokenB),
            pairFactory.INIT_CODE_PAIR_HASH()
        );
        assertEq(pair_fromAB, expectedPair);
        assertEq(pair_fromBA, expectedPair);
    }

    function _safeApprove(
        address token,
        address spender,
        uint256 value
    ) internal {
        // 0x095ea7b3 = bytes4(keccak256("approve(address,uint256)"))
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0x095ea7b3, spender, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "APPROVE_FAILED"
        );
    }

    function testAddLiquidity() public {
        address pairFromFactory = pairFactory.createPair(address(tokenA), address(tokenB));
        uint256 amountADesired = 1e18;
        uint256 amountAMin = amountADesired;

        uint256 amountBDesired = 4e18;
        uint256 amountBMin = amountBDesired;

        uint256 validDeadline = _validDeadline(); //to be made

        address lpRecipient = makeAddr("lpRecipient");
        address deadAddress = address(0x000000000000000000000000000000000000dEaD);

        uint256 amountProduct = amountADesired* amountBDesired;
        uint256 expectedTotalSupply = Math.sqrt(amountProduct);

        uint256 expectedLpToProvider = expectedTotalSupply - MINIMUM_LIQUIDITY;

        vm.startPrank(lp);
        tokenA.mint(lp,amountADesired);
        tokenB.mint(lp,amountBDesired);
        

        _safeApprove(address(tokenA), address(ammRouter), type(uint256).max);
        _safeApprove(address(tokenB), address(ammRouter), type(uint256).max);
        
        (uint256 amountA,uint256 amountB, uint256 liquidity) = ammRouter
        .addLiquidity(
                address(tokenA),
                address(tokenB),
                amountADesired,
                amountBDesired,
                amountAMin,
                amountBMin,
                lpRecipient,
                validDeadline
        );
        vm.stopPrank();
         
         (
            uint256 reserveA_fromAB,
            uint256 reserveB_fromAB,
            address pair_fromAB
        ) = ammRouter.getReserves(address(tokenA), address(tokenB));

        (
            uint256 reserveB_fromBA,
            uint256 reserveA_fromBA,
            address pair_fromBA
        ) = ammRouter.getReserves(address(tokenB), address(tokenA));
        
        uint256 deadLpBalance = TokenPair(pairFromFactory).balanceOf(
            deadAddress
        );

        assertEq(pair_fromAB, pairFromFactory);
        assertEq(pair_fromBA, pairFromFactory);
        assertEq(reserveA_fromAB, amountADesired);
        assertEq(reserveB_fromAB, amountBDesired);

        assertEq(reserveA_fromBA, amountADesired);
        assertEq(reserveB_fromBA, amountBDesired);

        assertEq(amountA, amountADesired);
        assertEq(amountB, amountBDesired);

        assertEq(liquidity, expectedLpToProvider);

        assertEq(
            TokenPair(pairFromFactory).balanceOf(lpRecipient),
            expectedLpToProvider
        );
        assertEq(deadLpBalance, MINIMUM_LIQUIDITY);
        assertEq(TokenPair(pairFromFactory).totalSupply(), expectedTotalSupply);


    }

     function testDeadLineExpiredAddLiquidity() public {
        uint256 amountADesired = 1e18;
        uint256 amountAMin = amountADesired;
        uint256 amountBDesired = 4e18;
        uint256 amountBMin = amountBDesired;
        uint256 validDeadline = _invalidDeadline();
        address lpRecipient = makeAddr("lpRecipient");
        vm.expectRevert(bytes("DEADLINE_EXPIRED"));
        ammRouter
            .addLiquidity(
                address(tokenA),
                address(tokenB),
                amountADesired,
                amountBDesired,
                amountAMin,
                amountBMin,
                lpRecipient,
                validDeadline
            );
    }

    function testIdenticalAddresses() public {
        vm.expectRevert(bytes("IDENTICAL_ADDRESSES"));
        ammRouter.addLiquidity(
            address(tokenA),
            address(tokenA),
            1,
            1,
            0,
            0,
            lp,
            _validDeadline()
        );
    }

    function testZeroAddresses() public {
        vm.expectRevert(bytes("ZERO_ADDRESS"));
        ammRouter.addLiquidity(
            address(0),
            address(tokenA),
            1,
            1,
            0,
            0,
            lp,
            _validDeadline()
        );
    }
    function testRemoveLiquidity() public {
        // Arrange: create pair and add initial liquidity via the router
        address pair = pairFactory.createPair(address(tokenA), address(tokenB));

        uint256 amountADesired = 1e18;
        uint256 amountBDesired = 4e18;
        uint256 amountAMin = amountADesired;
        uint256 amountBMin = amountBDesired;
        uint256 deadline = _validDeadline();
        address liquidityProvider = makeAddr("liquidityProvider");

        vm.startPrank(liquidityProvider);
        tokenA.mint(liquidityProvider, amountADesired);
        tokenB.mint(liquidityProvider, amountBDesired);

        // Router pulls tokens via transferFrom(msg.sender, pair, amount),
        // so the liquidityProvider must approve the router as spender.
        _safeApprove(address(tokenA), address(ammRouter), type(uint256).max);
        _safeApprove(address(tokenB), address(ammRouter), type(uint256).max);

        (uint256 amountA, uint256 amountB, uint256 liquidity) = ammRouter
            .addLiquidity(
                address(tokenA),
                address(tokenB),
                amountADesired,
                amountBDesired,
                amountAMin,
                amountBMin,
                liquidityProvider,
                deadline
            );

        // totalSupply = sqrt(amountA * amountB)
        uint256 amountProduct = amountADesired * amountBDesired;
        uint256 expectedTotalSupply = Math.sqrt(amountProduct);
        uint256 expectedLpToProvider = expectedTotalSupply - MINIMUM_LIQUIDITY;

        assertEq(amountA, amountADesired);
        assertEq(amountB, amountBDesired);
        assertEq(liquidity, expectedLpToProvider);
        assertEq(TokenPair(pair).balanceOf(liquidityProvider), liquidity);
        assertEq(TokenPair(pair).totalSupply(), expectedTotalSupply);

        (uint256 reserveABefore, uint256 reserveBBefore, ) = ammRouter
            .getReserves(address(tokenA), address(tokenB));

        assertEq(reserveABefore, amountADesired);
        assertEq(reserveBBefore, amountBDesired);

        uint256 beforeBurnBalanceAOfTokenPair = IERC20(address(tokenA))
            .balanceOf(pair);
        uint256 beforeBurnBalanceBOfTokenPair = IERC20(address(tokenB))
            .balanceOf(pair);

        assertEq(beforeBurnBalanceAOfTokenPair, amountADesired);
        assertEq(beforeBurnBalanceBOfTokenPair, amountBDesired);

        // Calculate expected amounts to be returned (proportional to liquidity burned)
        uint256 expectedAmountARemoved = (liquidity * reserveABefore) /
            expectedTotalSupply;
        uint256 expectedAmountBRemoved = (liquidity * reserveBBefore) /
            expectedTotalSupply;

        // Act: approve LP tokens to router and remove all liquidity
        _safeApprove(pair, address(ammRouter), type(uint256).max);

        (uint256 amountARemoved, uint256 amountBRemoved) = ammRouter
            .removeLiquidity(
                address(tokenA),
                address(tokenB),
                liquidity,
                expectedAmountARemoved,
                expectedAmountBRemoved,
                liquidityProvider,
                deadline
            );

        // Assert: LP tokens burned and underlying returned proportionally
        assertEq(TokenPair(pair).balanceOf(liquidityProvider), 0);
        assertEq(amountARemoved, expectedAmountARemoved);
        assertEq(amountBRemoved, expectedAmountBRemoved);
        assertEq(tokenA.balanceOf(liquidityProvider), expectedAmountARemoved);
        assertEq(tokenB.balanceOf(liquidityProvider), expectedAmountBRemoved);

        vm.stopPrank();
    }


    function testGetAmountsOutRevertsOnInvalidPath() public {
        address[] memory path = new address[](1);
        path[0] = address(tokenA);

        vm.expectRevert(bytes("INVALID_PATH"));
        ammRouter.getAmountsOut(1e18, path);
    }

    function testAddLiquidityRevertsWithoutApprovals() public {
        uint256 amountA = 1e18;
        uint256 amountB = 4e18;

        tokenA.mint(lp, amountA);
        tokenB.mint(lp, amountB);

        vm.startPrank(lp);
        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));
        ammRouter.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            amountA,
            amountB,
            lp,
            _validDeadline()
        );
        vm.stopPrank();
    }

    function testSwapTokensForExactTokensBasicSwap()
        public
    {
        // Arrange: Seed liquidity
        uint256 amountA = 10e18;
        uint256 amountB = 10e18;

        tokenA.mint(lp, amountA);
        tokenB.mint(lp, amountB);

        vm.startPrank(lp);
        _safeApprove(address(tokenA), address(ammRouter), type(uint256).max);
        _safeApprove(address(tokenB), address(ammRouter), type(uint256).max);
        ammRouter.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            0,
            0,
            lp,
            _validDeadline()
        );
        vm.stopPrank();

        // Get initial state
        (uint256 reserveABefore, uint256 reserveBBefore, ) = ammRouter
            .getReserves(address(tokenA), address(tokenB));

        address trader = makeAddr("trader");
        uint256 amountOut = 5e17; // 0.5 tokens
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        // Get expected input amount
        uint256[] memory expectedAmounts = ammRouter.getAmountsIn(amountOut, path);
        uint256 expectedAmountIn = expectedAmounts[0];

        // Get initial balances
        tokenA.mint(trader, expectedAmountIn * 2); // Give extra tokens
        uint256 traderBalanceABefore = tokenA.balanceOf(trader);
        uint256 traderBalanceBBefore = tokenB.balanceOf(trader);

        // Act: Perform swap
        vm.startPrank(trader);
        _safeApprove(address(tokenA), address(ammRouter), type(uint256).max);
        
        uint256[] memory amounts = ammRouter.swapTokensForExactTokens(
            amountOut,
            type(uint256).max,
            path,
            trader,
            _validDeadline()
        );
        vm.stopPrank();

        // Assert: Check amounts array
        assertEq(amounts.length, 2);
        assertEq(amounts[0], expectedAmountIn);
        assertEq(amounts[1], amountOut);

        // Assert: Check reserves updated correctly
        (uint256 reserveAAfter, uint256 reserveBAfter, ) = ammRouter.getReserves(
            address(tokenA),
            address(tokenB)
        );
        assertEq(reserveAAfter, reserveABefore + expectedAmountIn);
        assertEq(reserveBAfter, reserveBBefore - amountOut);

        // Assert: Check trader balances
        assertEq(tokenA.balanceOf(trader), traderBalanceABefore - expectedAmountIn);
        assertEq(tokenB.balanceOf(trader), traderBalanceBBefore + amountOut);
    }

    function testSwapTokensForExactTokensMultiHopSwapSwapsThroughPath()
        public
    {
        // Arrange: Create third token and pairs
        MockERC20 tokenC = new MockERC20("TokenC", "TKC", 18);

        uint256 amountA = 10e18;
        uint256 amountB = 10e18;
        uint256 amountC = 10e18;

        // Add liquidity to A-B pair
        tokenA.mint(lp, amountA);
        tokenB.mint(lp, amountB);

        vm.startPrank(lp);
        _safeApprove(address(tokenA), address(ammRouter), type(uint256).max);
        _safeApprove(address(tokenB), address(ammRouter), type(uint256).max);
        ammRouter.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            0,
            0,
            lp,
            _validDeadline()
        );

        // Add liquidity to B-C pair
        tokenB.mint(lp, amountB);
        tokenC.mint(lp, amountC);
        _safeApprove(address(tokenC), address(ammRouter), type(uint256).max);
        ammRouter.addLiquidity(
            address(tokenB),
            address(tokenC),
            amountB,
            amountC,
            0,
            0,
            lp,
            _validDeadline()
        );
        vm.stopPrank();

        // Perform swap A -> B -> C
        address trader = makeAddr("trader");
        uint256 amountOut = 5e17;
        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);

        uint256[] memory expectedAmounts = ammRouter.getAmountsIn(amountOut, path);
        uint256 expectedAmountIn = expectedAmounts[0];

        tokenA.mint(trader, expectedAmountIn * 2);
        uint256 traderBalanceCBefore = tokenC.balanceOf(trader);

        // Act
        vm.startPrank(trader);
        _safeApprove(address(tokenA), address(ammRouter), type(uint256).max);
        uint256[] memory amounts = ammRouter.swapTokensForExactTokens(
            amountOut,
            type(uint256).max,
            path,
            trader,
            _validDeadline()
        );
        vm.stopPrank();

        // Assert
        assertEq(amounts.length, 3);
        assertEq(amounts[0], expectedAmountIn);
        assertEq(amounts[1], expectedAmounts[1]);
        assertEq(amounts[2], amountOut);
        assertEq(tokenC.balanceOf(trader), traderBalanceCBefore + amountOut);
    }

    function testSwapTokensForExactTokensRevertsOnExcessiveInputAmount()
        public
    {
        // Arrange: Seed liquidity
        uint256 amountA = 10e18;
        uint256 amountB = 10e18;

        tokenA.mint(lp, amountA);
        tokenB.mint(lp, amountB);

        vm.startPrank(lp);
        _safeApprove(address(tokenA), address(ammRouter), type(uint256).max);
        _safeApprove(address(tokenB), address(ammRouter), type(uint256).max);
        ammRouter.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            0,
            0,
            lp,
            _validDeadline()
        );
        vm.stopPrank();

        address trader = makeAddr("trader");
        uint256 amountOut = 5e17;
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256[] memory requiredAmounts = ammRouter.getAmountsIn(amountOut, path);
        uint256 amountInMax = requiredAmounts[0] - 1; // Less than required

        tokenA.mint(trader, requiredAmounts[0]);

        vm.startPrank(trader);
        _safeApprove(address(tokenA), address(ammRouter), type(uint256).max);

        vm.expectRevert(bytes("EXCESSIVE_INPUT_AMOUNT"));
        ammRouter.swapTokensForExactTokens(
            amountOut,
            amountInMax,
            path,
            trader,
            _validDeadline()
        );
        vm.stopPrank();
    }

    function testSwapTokensForExactTokensRevertsOnDeadlineExpired() public {
        // Arrange: Seed liquidity
        uint256 amountA = 10e18;
        uint256 amountB = 10e18;

        tokenA.mint(lp, amountA);
        tokenB.mint(lp, amountB);

        vm.startPrank(lp);
        _safeApprove(address(tokenA), address(ammRouter), type(uint256).max);
        _safeApprove(address(tokenB), address(ammRouter), type(uint256).max);
        ammRouter.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            0,
            0,
            lp,
            _validDeadline()
        );
        vm.stopPrank();

        address trader = makeAddr("trader");
        uint256 amountOut = 5e17;
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256[] memory requiredAmounts = ammRouter.getAmountsIn(amountOut, path);
        tokenA.mint(trader, requiredAmounts[0]);

        vm.startPrank(trader);
        _safeApprove(address(tokenA), address(ammRouter), type(uint256).max);

        vm.expectRevert(bytes("DEADLINE_EXPIRED"));
        ammRouter.swapTokensForExactTokens(
            amountOut,
            type(uint256).max,
            path,
            trader,
            _invalidDeadline()
        );
        vm.stopPrank();
    }

    function testSwapTokensForExactTokensRespectsToAddress() public {
        // Arrange: Seed liquidity
        uint256 amountA = 10e18;
        uint256 amountB = 10e18;

        tokenA.mint(lp, amountA);
        tokenB.mint(lp, amountB);

        vm.startPrank(lp);
        _safeApprove(address(tokenA), address(ammRouter), type(uint256).max);
        _safeApprove(address(tokenB), address(ammRouter), type(uint256).max);
        ammRouter.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            0,
            0,
            lp,
            _validDeadline()
        );
        vm.stopPrank();

        address trader = makeAddr("trader");
        address recipient = makeAddr("recipient");
        uint256 amountOut = 5e17;
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256[] memory requiredAmounts = ammRouter.getAmountsIn(amountOut, path);
        tokenA.mint(trader, requiredAmounts[0]);
        uint256 recipientBalanceBBefore = tokenB.balanceOf(recipient);

        // Act
        vm.startPrank(trader);
        _safeApprove(address(tokenA), address(ammRouter), type(uint256).max);
        ammRouter.swapTokensForExactTokens(
            amountOut,
            type(uint256).max,
            path,
            recipient,
            _validDeadline()
        );
        vm.stopPrank();

        // Assert: Recipient received the tokens
        assertEq(tokenB.balanceOf(recipient), recipientBalanceBBefore + amountOut);
        assertEq(tokenB.balanceOf(trader), 0);
    }

}
