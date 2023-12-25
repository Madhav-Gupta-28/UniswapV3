// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.14;

import "./interfaces/IUniswapV3PoolDeployer.sol";
import "./UniswapV3Pool.sol";

contract UniswapV3Factory is IUniswapV3PoolDeployer{

    // Errors
    error TokensMustBeDifferent();
    error UnsupportedTickSpacing();
    error TokenXCannotBeZero();
    error PoolAlreadyExists();

    // Events
    event PoolCreated(
        address indexed token0,
        address indexed token1,
        uint24 indexed tickSpacing,
        address pool
    );

    PoolParameters public parameters;

    // Mappings
    mapping(uint24 => bool) public tickSpacings; // Allowed TickSpacking mapping
    mapping(address => mapping(address => mapping(uint24 => address))) public pools;
    mapping(uint24 => uint24) public fees;



    constructor() {
        fees[500] = 10;
        fees[300] = 60;
    }

    
    function createPool(
        address tokenX,
        address tokenY,
        uint24 tickSpacing
    ) public returns (address pool){

        if(tokenX == tokenY) revert TokensMustBeDifferent();
        if(tickSpacings[tickSpacing] != true ) revert UnsupportedTickSpacing();

        (tokenX , tokenY) =  tokenX < tokenY 
            ? (tokenX , tokenY)
            : (tokenY,tokenX);

        if(tokenX == address(0)) revert TokenXCannotBeZero();
        if(pools[tokenX][tokenY][tickSpacing] != address(0)) revert PoolAlreadyExists();

        parameters = PoolParameters({
            factory : address(this),
            token0 : tokenX,
            token1 : tokenY,
            tickSpacing : tickSpacing
        });

        pool = address(
            new UniswapV3Pool{
                salt : keccak256(abi.encodePacked(tokenX,tokenY,tickSpacing))
            }()
        );

        delete parameters;

        pools[tokenX][tokenY][tickSpacing] = pool;
        pools[tokenY][tokenX][tickSpacing] = pool;

        emit PoolCreated(tokenX, tokenY, tickSpacing, pool);




    }





}

