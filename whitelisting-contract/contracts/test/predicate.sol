pragma solidity ^0.8.0;

contract AcceptEven {
    function validateArguments(bytes calldata arguments) external pure returns (bool) {
        return arguments.length == 32 && uint8(arguments[31]) % 2 == 0;
    }
}
