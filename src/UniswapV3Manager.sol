// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.14;


import "./interfaces/IERC20.sol";
import "./UniswapV3Pool.sol";



contract UniswapV3Manager {

    function mint(address poolAddress_ , int24 lowertick , int24 uppertick , uint128 amount , bytes calldata data) public {
        UniswapV3Pool(poolAddress_).mint(msg.sender, lowertick, uppertick, amount, data);
    }

    function swap(address poolAddress_, bytes calldata data) public {
        UniswapV3Pool(poolAddress_).swap(msg.sender, data);
    }
}