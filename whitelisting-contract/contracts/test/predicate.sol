pragma solidity ^0.8.0;

contract AcceptEven {
    function validateArguments(bytes calldata arguments) external pure returns (bool) {
        return abi.decode(arguments, (uint)) % 2 == 0;
    }
}
