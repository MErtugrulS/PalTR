using UnrealBuildTool;

public class PalTRUIAssetBuilder : ModuleRules
{
    public PalTRUIAssetBuilder(ReadOnlyTargetRules Target) : base(Target)
    {
        PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;

        PublicDependencyModuleNames.AddRange(
            new[]
            {
                "Core",
                "CoreUObject",
                "Engine",
                "UMG"
            }
        );

        PrivateDependencyModuleNames.AddRange(
            new[]
            {
                "AssetRegistry",
                "SlateCore",
                "UMGEditor",
                "UnrealEd"
            }
        );
    }
}
