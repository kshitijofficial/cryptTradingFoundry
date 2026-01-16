// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ITokenPair} from "../interfaces/ITokenPair.sol";
import {IERC20} from "../interfaces/IERC20.sol";

contract TokenPair is ERC20, ReentrancyGuard, ITokenPair {
    address public factory;
    address public tokenA;
    address public tokenB;

    uint256 private reserveA;
    uint256 private reserveB;

    uint256 private blockTimestampLast;

    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;

    bytes4 private constant SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));

    constructor() ERC20("LP Token", "LPT") {
        factory = msg.sender;
    }

    function initialize(address _tokenA, address _tokenB) external {
        require(msg.sender == factory, "Not Factory");
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    function _setReserves(uint256 balance0, uint256 balance1) private {
        reserveA = balance0;
        reserveB = balance1;
        blockTimestampLast = block.timestamp;
        emit Sync(reserveA, reserveB);
    }

    function getReserves() public view returns (uint256 _reserveA, uint256 _reserveB, uint256 _blockLastTimestamp) {
        _reserveA = reserveA;
        _reserveB = reserveB;
        _blockLastTimestamp = blockTimestampLast;
    }

    function mint(address to) external nonReentrant returns (uint256 liquidity) {
        (uint256 _reserveA, uint256 _reserveB,) = getReserves();

        uint256 balanceA = IERC20(tokenA).balanceOf(address(this));
        uint256 balanceB = IERC20(tokenB).balanceOf(address(this));

        uint256 amountA = balanceA - _reserveA;
        uint256 amountB = balanceB - _reserveB;

        uint256 _totalSupply = totalSupply(); //total supply of the lp tokens

        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amountA * amountB) - MINIMUM_LIQUIDITY;
            _mint(address(0xdead), MINIMUM_LIQUIDITY); //permanently lock the first Minting amount
        } else {
            liquidity = Math.min((amountA * _totalSupply) / _reserveA, (amountB * _totalSupply) / _reserveB);
        }
        require(liquidity > 0, "INSUFFICIENT_LIQUIDITY");
        _mint(to, liquidity);
        _setReserves(balanceA, balanceB);
        emit Mint(msg.sender, amountA, amountB);
    }

    function _safeTransfer(address token, address to, uint256 value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Transfer failed");
    }

    function burn(address to) external returns (uint256 amountA, uint256 amountB) {
        address _tokenA = tokenA;
        address _tokenB = tokenB;

        uint256 balanceA = IERC20(_tokenA).balanceOf(address(this));
        uint256 balanceB = IERC20(_tokenB).balanceOf(address(this));

        uint256 liquidity = balanceOf(address(this));

        uint256 _totalSupply = totalSupply();

        amountA = (liquidity * balanceA) / _totalSupply;
        amountB = (liquidity * balanceB) / _totalSupply;

        require(amountA > 0 && amountB > 0, "INSUFFICIENT BURNING LIQUIDITY");
        _burn(address(this), liquidity);

        _safeTransfer(_tokenA, to, amountA);
        _safeTransfer(_tokenB, to, amountB);

        balanceA = IERC20(_tokenA).balanceOf(address(this));
        balanceB = IERC20(_tokenB).balanceOf(address(this));

        _setReserves(balanceA, balanceB);
        emit Burn(msg.sender, amountA, amountB, to);
    }

    function swap(uint256 amountAOut, uint256 amountBOut, address to) external nonReentrant {
        require(amountAOut > 0 || amountBOut > 0, "INVALID_OUTPUT_AMOUNT");
        (uint256 _reserveA, uint256 _reserveB,) = getReserves();

        require(amountAOut < _reserveA && amountBOut < _reserveB, "INSUFFICIENT_RESERVE");
        address _tokenA = tokenA;
        address _tokenB = tokenB;

        require(to != _tokenA && to != _tokenB, "INVALID_OUTPUT_ADDRESS");

        if (amountAOut > 0) _safeTransfer(_tokenA, to, amountAOut);
        if (amountBOut > 0) _safeTransfer(_tokenB, to, amountBOut);

        uint256 balance0 = IERC20(_tokenA).balanceOf(address(this));
        uint256 balance1 = IERC20(_tokenB).balanceOf(address(this));

        uint256 amountAIn = balance0 > _reserveA - amountAOut ? balance0 - (_reserveA - amountAOut) : 0;
        uint256 amountBIn = balance1 > _reserveB - amountBOut ? balance1 - (_reserveB - amountBOut) : 0;

        require(amountAIn > 0 || amountBIn > 0, "INSUFFICIENT_INPUT_AMOUNT");
        //(balance0 - amountAIn * 0.002) × (balance1 - amountBIn * 0.002) ≥ reserveA × reserveB
        {
            uint256 balance0Adjusted = balance0 * 1000 - amountAIn * 2;
            uint256 balance1Adjusted = balance1 * 1000 - amountBIn * 2;

            require(balance0Adjusted * balance1Adjusted >= reserveA * reserveB * 1000 ** 2, "INSUFFICIENT_LIQUIDITY");
        }
        _setReserves(balance0, balance1);
        emit Swap(msg.sender, amountAIn, amountBIn, amountAOut, amountBOut, to);
    }
}
