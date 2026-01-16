// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {PairFactory} from "src/contracts/PairFactory.sol";
import {TokenPair} from "src/contracts/TokenPair.sol";

contract PairFactoryTest is Test {
    PairFactory internal pairFactory;
    address internal tokenA;
    address internal tokenB;

    event PairCreated(address indexed tokenA, address indexed tokenB, address pair, uint256);
    
    function setUp() public {
        tokenA = makeAddr("tokenA");
        tokenB = makeAddr("tokenB");
        pairFactory = new PairFactory();
    }

    function _sortTokens(address a, address b) internal pure returns (address token0, address token1) {
        require(a != b, "IDENTICAL_ADDRESSES");
        (token0, token1) = a < b ? (a, b) : (b, a);
        require(token0 != address(0), "ZERO_ADDRESS");
        return (token0,token1);
    }

    function _computeCreate2Address(
        address factory,
        address token0,
        address token1
    ) internal pure returns(address predicted){
        bytes32 salt = keccak256(abi.encodePacked(token0,token1));
        bytes32 initCodeHash = keccak256(type(TokenPair).creationCode);
        bytes32 digest = keccak256(
            abi.encodePacked(bytes1(0xff),factory,salt,initCodeHash)
        );
        predicted = address(uint160(uint256(digest)));
    }


    function testCreatePair() public {
        (address token0,address token1) = _sortTokens(tokenA, tokenB);
        
        address expectedPair = _computeCreate2Address(
            address(pairFactory),
            token0,
            token1
        );
        uint256 getPairLengthBefore = pairFactory.allPairsLength();

        vm.expectEmit(true,true,false,true,address(pairFactory));
        emit PairCreated(token0, token1, expectedPair, 1);

        address pair = pairFactory.createPair(token0,token1);
        uint256 getPairLengthAfter = pairFactory.allPairsLength();

        assertEq(pairFactory.getPair(token0,token1),pair);
        assertEq(pairFactory.getPair(token1,token0),pair);
        assertEq(pairFactory.allPairs(getPairLengthAfter -1),pair);
        assertEq(getPairLengthBefore+1,getPairLengthAfter);
        assertEq(TokenPair(pair).factory(),address(pairFactory));
        assertEq(TokenPair(pair).tokenA(),token0);
        assertEq(TokenPair(pair).tokenB(),token1);
    }

    function testCreatePairOrderInvariance() public {
        address pair = pairFactory.createPair(tokenA, tokenB);
        address pairAB = pairFactory.getPair(tokenA, tokenB);
        address pairBA = pairFactory.getPair(tokenB, tokenA);
        assertEq(pairAB, pairBA);
        assertEq(pair, pairBA);
        assertEq(pair, pairAB);

        vm.expectRevert(bytes("PAIR_ALREADY_EXISTS"));
        pairFactory.createPair(tokenA, tokenB);

        vm.expectRevert(bytes("PAIR_ALREADY_EXISTS"));
        pairFactory.createPair(tokenB, tokenA);
    }

    function testCreatePairRevertsOnIdenticalAddresses() public {
        vm.expectRevert(bytes("IDENTICAL_ADDRESSES"));
        pairFactory.createPair(tokenA, tokenA);

        vm.expectRevert(bytes("IDENTICAL_ADDRESSES"));
        pairFactory.createPair(tokenB, tokenB);
    }

    function testCreatePairRevertsOnZeroAddresses() public {
        vm.expectRevert(bytes("ZERO_ADDRESS"));
        pairFactory.createPair(address(0), tokenB);

        vm.expectRevert(bytes("ZERO_ADDRESS"));
        pairFactory.createPair((tokenA), address(0));
    }

}
