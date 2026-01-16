// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

interface IPairFactory {
    event PairCreated(address indexed tokenA, address indexed tokenB, address pair, uint256);

    function getPair(address tokenA, address tokenB) external view returns (address pair);

    function allPairs(uint256) external view returns (address pair);

    function allPairsLength() external view returns (uint256);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function INIT_CODE_PAIR_HASH() external view returns (bytes32);
}
