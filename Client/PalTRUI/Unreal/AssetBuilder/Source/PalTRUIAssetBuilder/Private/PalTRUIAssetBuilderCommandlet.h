#pragma once

#include "Commandlets/Commandlet.h"
#include "PalTRUIAssetBuilderCommandlet.generated.h"

UCLASS()
class PALTRUIASSETBUILDER_API UPalTRUIAssetBuilderCommandlet : public UCommandlet
{
    GENERATED_BODY()

public:
    UPalTRUIAssetBuilderCommandlet();

    virtual int32 Main(const FString& Params) override;
};
