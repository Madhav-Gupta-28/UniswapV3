// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.14;

import "./lib/Tick.sol";
import "./lib/Position.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IUniswapV3MintCallback.sol";
import "./interfaces/IUniswapV3SwapCallback.sol";


contract UniswapV3Pool {

    using Tick for mapping(int24 => Tick.Info);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;

    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = -MIN_TICK;

    // Pool tokens, immutable
    address public immutable token0;
    address public immutable token1;

    // Here I am packing variable 
    struct Slot0{
        uint160 sqrtPriceX96;
        int24 tick;
    }

    Slot0 public slot0;

    // Struct for Storing Data for Callbacks
    struct CallbackData{
        address token0;
        address token1;
        address payer;
    }

    uint128 public liquidity; // Keeping track of amount of Liquidity

    // Ticks Info
    mapping(int24 => Tick.Info) public ticks;
    mapping(bytes32 => Position.Info) public positions;

    // Initialzing variables in the constructor
    constructor(address token0_ , address token1_ , uint160  sqrtPriceX96_ , int24 tick_){
        token0  = token0_;
        token1 = token1_;
        slot0 = Slot0(sqrtPriceX96_,tick_);
    }

    // Errors
    error InvalidTickRange();
    error ZeroLiquidity();
    error InsufficientInputAmount();

    // Events
    event Mint( address sender, address indexed owner, int24 indexed tickLower,int24 indexed tickUpper,uint128 amount,uint256 amount0,uint256 amount1  );

    event Swap(
        address indexed sender,
        address indexed recipient,
        int256 amount0,
        int256 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick
    );




    function mint(address owner , int24 lowertick , int24 uppertick , uint128 amount , bytes calldata data) external returns(uint256 amount0 , uint256 amount1){
        if(
            lowertick < MIN_TICK || 
            uppertick > MAX_TICK ||
            lowertick >= uppertick
        ){
            revert InvalidTickRange();
        }

        if(amount <=  0) revert ZeroLiquidity();

        ticks.update(lowertick,amount);
        ticks.update(uppertick,amount);

        Position.Info storage position = positions.get(owner,lowertick,uppertick);

        position.update(amount);


        amount0 = 0.998976618347425280 ether;
        amount1 = 5000 ether;

        liquidity += uint128(amount);


        uint256 balance0before;
        uint256 balance1before;

        if(amount0 > 0 ) balance0before = balance0() ;
        if(amount1 > 0) balance1before = balance1();

       IUniswapV3MintCallback(msg.sender).uniswapV3MintCallback(amount0,amount1,data);



        if (amount0 > 0 && balance0before + amount0 > balance0())
        revert InsufficientInputAmount();
        if (amount1 > 0 && balance1before + amount1 > balance1())
        revert InsufficientInputAmount();

        emit Mint(msg.sender, owner, lowertick, uppertick, amount, amount0, amount1);

    }


    function swap(
        address recipient , bytes calldata data
        ) public returns(int256 amount0 , int256 amount1){
        int24 nextTick = 85184;
        uint160 nextPrice = 5604469350942327889444743441197;

        amount0 = -0.008396714242162444 ether;
        amount1 = 42 ether;

        (slot0.tick , slot0.sqrtPriceX96) = (nextTick , nextPrice);

        IERC20(token0).transfer(recipient, uint256(-amount0));
            uint256 balance1Before = balance1();
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(
            amount0,
            amount1,
            data
    );
        if (balance1Before + uint256(amount1) < balance1())
            revert InsufficientInputAmount();

             emit Swap(
            msg.sender,
            recipient,
            amount0,
            amount1,
            slot0.sqrtPriceX96,
            liquidity,
            slot0.tick
            );

    



    }



    // Helper Functions 
    function balance0() internal returns (uint256 balance) {
        balance = IERC20(token0).balanceOf(address(this));
    }

    function balance1() internal returns (uint256 balance) {
        balance = IERC20(token1).balanceOf(address(this));
    }

}
