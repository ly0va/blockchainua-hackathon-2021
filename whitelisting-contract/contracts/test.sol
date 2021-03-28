pragma solidity ^0.8.0;

contract Test {
    event Called(string indexed method);

    function foo(uint a) external returns (uint) {
        emit Called('foo');
        return a * a;
    }

    function bar(uint a, uint b) external returns (uint) {
        emit Called('bar');
        return a + b;
    }

    fallback() external payable {
        emit Called('fallback');
    }

    receive() external payable {
        emit Called('receive');
    }
}
