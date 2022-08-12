// SPDX-License-Identifier: ALEX

import "C:/Users/Alex Nikolic/Desktop/CFCoding/UseCases/shares/openzeppelin-contracts/contracts/access/Ownable.sol";

pragma solidity ^0.8.0;

abstract contract RestrictionCodes is Ownable {
    mapping(uint8 => string) codeToText;

    constructor() {
        codeToText[0x50] = "Transfer Failed";
        codeToText[0x51] = "Transfer successful";
        codeToText[0x54] = "Insufficient Funds";
        codeToText[0x59] = "No Funds";
        codeToText[0x5A] = "Receiver not identified";
        codeToText[0x42] = "Transfer Paused";
    }

    /** @notice add restrictionCodes which meaaning can be requested through the Stock contract
     * @dev restrictionCodes need to be compliant with the ERC1066 standard
     */
    function updateRestrictionCodes(uint8[] memory code, string[] memory text)
        public
        onlyOwner
    {
        require(
            code.length == text.length,
            "provide equal amount of code and text"
        );
        for (uint256 i = 0; i < code.length; i++) {
            codeToText[code[i]] = text[i];
        }
    }
}
