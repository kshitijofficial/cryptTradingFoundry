// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {IPairFactory} from "../interfaces/IPairFactory.sol";
import {TokenPair} from "./TokenPair.sol";
import {ITokenPair} from "../interfaces/ITokenPair.sol";

contract PairFactory is IPairFactory {

    bytes32 public constant INIT_CODE_PAIR_HASH = 
     keccak256(abi.encodePacked(type(TokenPair).creationCode));
     
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    function allPairsLength() external view returns (uint256){
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, "IDENTICAL_ADDRESSES");
        //Step 1: sorting tokens
        (address _tokenA, address _tokenB) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        require(_tokenA != address(0), "ZERO_ADDRESS");
        require(getPair[_tokenA][_tokenB] == address(0), "PAIR_ALREADY_EXISTS");

        //Step 2: Prepare for create2 arguments
        bytes memory bytecode = type(TokenPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(_tokenA, _tokenB));

        //Step 3: Deploy the token pair on the address calculated
        //with with the factory's address, bytecode and salt

        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }

        ITokenPair(pair).initialize(_tokenA, _tokenB);

        getPair[_tokenA][_tokenB] = pair;
        getPair[_tokenB][_tokenA] = pair;

        allPairs.push(pair);
        emit PairCreated(_tokenA, _tokenB, pair, allPairs.length);
    }
}
