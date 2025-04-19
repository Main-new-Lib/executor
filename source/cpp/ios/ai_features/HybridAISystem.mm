#include "../../ios_compat.h"
#include "HybridAISystem.h"
#include "local_models/LocalModelBase.h"
#include "local_models/ScriptGenerationModel.h"
#include "vulnerability_detection/VulnerabilityDetector.h"
#include <iostream>
#include <sstream>
#include <thread>
#include <algorithm>
#include <cctype>
#include <regex>
#include <random>
#include <set>

namespace iOS {
namespace AIFeatures {

// Constructor
HybridAISystem::HybridAISystem()
    : m_initialized(false),
      m_localModelsLoaded(false),
      m_isInLowMemoryMode(false),
      m_networkConnected(false),
      m_onlineMode(OnlineMode::Auto),
      m_scriptAssistantModel(nullptr),
      m_scriptGeneratorModel(nullptr),
      m_debugAnalyzerModel(nullptr),
      m_patternRecognitionModel(nullptr),
      m_totalMemoryUsage(0),
      m_maxMemoryAllowed(200 * 1024 * 1024), // 200MB default
      m_responseCallback(nullptr) {
}

// Destructor
HybridAISystem::~HybridAISystem() {
    // Clean up resources
    for (const auto& pair : m_modelCache) {
        // Nothing to do here with our locally trained models
    }
}

// Initialize the AI system
bool HybridAISystem::Initialize(const std::string& modelPath, 
                              const std::string& apiEndpoint, 
                              const std::string& apiKey,
                              std::function<void(float)> progressCallback) {
    if (m_initialized) {
        return true;
    }
    
    try {
        m_modelPath = modelPath;
        m_apiEndpoint = apiEndpoint;
        m_apiKey = apiKey;
        
        // Create models directory if it doesn't exist
        NSString* dirPath = [NSString stringWithUTF8String:modelPath.c_str()];
        NSFileManager* fileManager = [NSFileManager defaultManager];
        
        if (![fileManager fileExistsAtPath:dirPath]) {
            NSError* error = nil;
            BOOL success = [fileManager createDirectoryAtPath:dirPath
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:&error];
            if (!success) {
                std::cerr << "HybridAISystem: Failed to create models directory: " 
                         << [[error localizedDescription] UTF8String] << std::endl;
                return false;
            }
        }
        
        // Initialize local models
        if (progressCallback) progressCallback(0.1f);
        
        // Initialize Script Generator model
        auto scriptGenerator = std::make_shared<LocalModels::ScriptGenerationModel>();
        bool scriptGenInitialized = scriptGenerator->Initialize(modelPath + "/script_generator");
        
        if (scriptGenInitialized) {
            m_scriptGeneratorModel = scriptGenerator.get();
            m_modelCache["script_generator"] = static_cast<void*>(scriptGenerator.get());
            m_loadedModelNames.push_back("script_generator");
        } else {
            std::cerr << "HybridAISystem: Failed to initialize script generator model" << std::endl;
        }
        
        if (progressCallback) progressCallback(0.3f);
        
        // Initialize Vulnerability Detector
        auto vulnerabilityDetector = std::make_shared<VulnerabilityDetection::VulnerabilityDetector>();
        bool vulnerabilityInitialized = vulnerabilityDetector->Initialize(modelPath + "/vulnerability_detector");
        
        if (vulnerabilityInitialized) {
            m_patternRecognitionModel = vulnerabilityDetector.get();
            m_modelCache["vulnerability_detector"] = static_cast<void*>(vulnerabilityDetector.get());
            m_loadedModelNames.push_back("vulnerability_detector");
        } else {
            std::cerr << "HybridAISystem: Failed to initialize vulnerability detector" << std::endl;
        }
        
        if (progressCallback) progressCallback(0.5f);
        
        // Initialize Script Debugging model
        // In this implementation, we'll reuse the script generator for debugging
        if (scriptGenInitialized) {
            m_debugAnalyzerModel = scriptGenerator.get();
        }
        
        if (progressCallback) progressCallback(0.7f);
        
        // Initialize SelfModifyingCodeSystem for enhanced AI capabilities
        m_selfModifyingSystem = std::make_shared<SelfModifyingCodeSystem>();
        bool selfModifyingInitialized = m_selfModifyingSystem->Initialize(modelPath + "/self_modifying");
        
        if (selfModifyingInitialized) {
            std::cout << "HybridAISystem: Self-modifying code system initialized successfully" << std::endl;
        } else {
            std::cerr << "HybridAISystem: Warning - Self-modifying code system initialization failed" << std::endl;
            // Continue anyway, as we can recover later
        }
        
        // Load script templates
        LoadScriptTemplates();
        
        if (progressCallback) progressCallback(0.9f);
        
        // Check network connectivity
        m_networkConnected = CheckNetworkConnectivity();
        
        m_initialized = true;
        m_localModelsLoaded = true;
        
        if (progressCallback) progressCallback(1.0f);
        
        std::cout << "HybridAISystem: Successfully initialized" << std::endl;
        return true;
    } catch (const std::exception& e) {
        std::cerr << "HybridAISystem: Exception during initialization: " << e.what() << std::endl;
        return false;
    }
}

// Process a request
void HybridAISystem::ProcessRequest(const AIRequest& request, ResponseCallback callback) {
    if (!callback) {
        return;
    }
    
    if (!m_initialized) {
        AIResponse response;
        response.m_success = false;
        response.m_errorMessage = "AI system not initialized";
        callback(response);
        return;
    }
    
    // Process request in background thread
    std::thread([this, request, callback]() {
        AIResponse response = ProcessRequestSync(request);
        callback(response);
    }).detach();
}

// Process a request synchronously
HybridAISystem::AIResponse HybridAISystem::ProcessRequestSync(const AIRequest& request) {
    AIResponse response;
    
    // Check if initialized
    if (!m_initialized) {
        response.m_success = false;
        response.m_errorMessage = "AI system not initialized";
        return response;
    }
    
    // Check if we should use online mode
    bool useOnline = false;
    
    if (!request.m_forceOffline) {
        switch (m_onlineMode) {
            case OnlineMode::Auto:
                useOnline = m_networkConnected;
                break;
                
            case OnlineMode::PreferOffline:
                useOnline = false; // Default to offline
                break;
                
            case OnlineMode::PreferOnline:
                useOnline = m_networkConnected;
                break;
                
            case OnlineMode::OfflineOnly:
                useOnline = false;
                break;
                
            case OnlineMode::OnlineOnly:
                useOnline = m_networkConnected;
                break;
        }
    }
    
    // Start timing
    auto startTime = std::chrono::high_resolution_clock::now();
    
    // Process request based on type
    if (request.m_requestType == "script_generation") {
        // Try online processing if enabled
        if (useOnline) {
            response = ProcessRequestOnline(request);
            
            // If online processing failed, fall back to offline
            if (!response.m_success) {
                response = ProcessScriptGeneration(request);
                response.m_usedOnlineMode = false;
            } else {
                response.m_usedOnlineMode = true;
            }
        } else {
            // Use offline processing
            response = ProcessScriptGeneration(request);
            response.m_usedOnlineMode = false;
        }
    } else if (request.m_requestType == "debug") {
        // Try online processing if enabled
        if (useOnline) {
            response = ProcessRequestOnline(request);
            
            // If online processing failed, fall back to offline
            if (!response.m_success) {
                response = ProcessScriptDebugging(request);
                response.m_usedOnlineMode = false;
            } else {
                response.m_usedOnlineMode = true;
            }
        } else {
            // Use offline processing
            response = ProcessScriptDebugging(request);
            response.m_usedOnlineMode = false;
        }
    } else {
        // General query
        // Try online processing if enabled
        if (useOnline) {
            response = ProcessRequestOnline(request);
            
            // If online processing failed, fall back to offline
            if (!response.m_success) {
                response = ProcessGeneralQuery(request);
                response.m_usedOnlineMode = false;
            } else {
                response.m_usedOnlineMode = true;
            }
        } else {
            // Use offline processing
            response = ProcessGeneralQuery(request);
            response.m_usedOnlineMode = false;
        }
    }
    
    // Set processing time
    auto endTime = std::chrono::high_resolution_clock::now();
    response.m_processingTime = std::chrono::duration_cast<std::chrono::milliseconds>(
        endTime - startTime).count();
    
    // Add to request history
    m_requestHistory.push_back(request);
    
    // Add to response history
    m_responseHistory.push_back(response);
    
    // Trim history if needed
    if (m_requestHistory.size() > 100) {
        m_requestHistory.erase(m_requestHistory.begin());
        m_responseHistory.erase(m_responseHistory.begin());
    }
    
    return response;
}

// Generate a script
void HybridAISystem::GenerateScript(const std::string& description, const std::string& context, 
                               std::function<void(const std::string&)> callback,
                               bool useOnline) {
    if (!callback) {
        return;
    }
    
    // Create request
    AIRequest request(description, context, "script_generation", !useOnline);
    
    // Process request
    ProcessRequest(request, [callback](const AIResponse& response) {
        if (response.m_success) {
            callback(response.m_scriptCode.empty() ? response.m_content : response.m_scriptCode);
        } else {
            callback("Error: " + response.m_errorMessage);
        }
    });
}

// Debug a script
void HybridAISystem::DebugScript(const std::string& script, 
                            std::function<void(const std::string&)> callback,
                            bool useOnline) {
    if (!callback) {
        return;
    }
    
    // Create request
    AIRequest request("Debug this script", script, "debug", !useOnline);
    
    // Process request
    ProcessRequest(request, [callback](const AIResponse& response) {
        if (response.m_success) {
            callback(response.m_content);
        } else {
            callback("Error: " + response.m_errorMessage);
        }
    });
}

// Process a general query
HybridAISystem::AIResponse HybridAISystem::ProcessGeneralQuery(const AIRequest& request) {
    AIResponse response;
    
    try {
        // Get GeneralAssistantModel from AISystemInitializer
        auto initializer = AISystemInitializer::GetInstance();
        auto generalAssistant = initializer->GetGeneralAssistantModel();
        
        if (generalAssistant && generalAssistant->IsInitialized()) {
            // Use the model's sophisticated processing
            response = generalAssistant->ProcessQuery(request);
        } else {
            // Fall back to rule-based processing if model is not available
            std::string query = request.m_query;
            std::transform(query.begin(), query.end(), query.begin(), 
                          [](unsigned char c) { return std::tolower(c); });
            
            std::stringstream output;
            
            // Handle script generation requests
            if (query.find("generat") != std::string::npos && 
                (query.find("script") != std::string::npos || query.find("code") != std::string::npos)) {
                
                output << "To generate a script, please provide a description of what you want the script to do.\n\n";
                output << "For example:\n";
                output << "- Generate a script for ESP\n";
                output << "- Create a speed hack script\n";
                output << "- Make an aimbot script\n";
                
                response.m_success = true;
                response.m_content = output.str();
                
                response.m_suggestions.push_back("Generate ESP script");
                response.m_suggestions.push_back("Generate speed hack");
                response.m_suggestions.push_back("Generate aimbot");
                
                return response;
            }
            
            // Handle debug requests
            if (query.find("debug") != std::string::npos || 
                query.find("fix") != std::string::npos || 
                query.find("error") != std::string::npos) {
                
                output << "To debug a script, please provide the script code along with your question.\n\n";
                output << "For example:\n";
                output << "- Debug this script: [paste your script here]\n";
                output << "- Fix errors in: [paste your script here]\n";
                
                response.m_success = true;
                response.m_content = output.str();
                
                return response;
            }
            
            // Handle help requests
            if (query.find("help") != std::string::npos || 
                query.find("how to") != std::string::npos || 
                query.find("explain") != std::string::npos) {
                
                output << "I'm here to help you with Lua scripting for Roblox games. Here are some things I can do:\n\n";
                output << "- Generate scripts based on your description\n";
                output << "- Debug existing scripts\n";
                output << "- Explain how to achieve specific effects or behaviors\n";
                output << "- Answer questions about Lua programming\n";
                output << "- Provide tips and best practices\n\n";
                
                output << "What would you like help with today?";
                
                response.m_success = true;
                response.m_content = output.str();
                
                response.m_suggestions.push_back("Generate a script");
                response.m_suggestions.push_back("Debug a script");
                response.m_suggestions.push_back("Explain Lua functions");
                
                return response;
            }
            
            // Handle script execution questions
            if (query.find("execute") != std::string::npos || 
                query.find("run") != std::string::npos) {
                
                output << "To execute a script, you can:\n\n";
                output << "1. Press the Execute button in the script editor\n";
                output << "2. Use the context menu on a saved script and select Execute\n";
                output << "3. Create a hotkey for quick execution\n\n";
                
                output << "Would you like to execute a specific script?";
                
                response.m_success = true;
                response.m_content = output.str();
                
                return response;
            }
            
            // Handle vulnerability scan requests
            if (query.find("vulnerabilit") != std::string::npos || 
                query.find("scan") != std::string::npos || 
                query.find("exploit") != std::string::npos || 
                query.find("backdoor") != std::string::npos) {
                
                output << "I can scan for vulnerabilities in Roblox games. To start a scan:\n\n";
                output << "1. Join the game you want to scan\n";
                output << "2. Click on 'Scan for Vulnerabilities' in the tools menu\n";
                output << "3. Wait for the scan to complete\n\n";
                
                output << "Would you like me to scan the current game for vulnerabilities?";
                
                response.m_success = true;
                response.m_content = output.str();
                
                response.m_suggestions.push_back("Scan current game");
                response.m_suggestions.push_back("View vulnerability types");
                response.m_suggestions.push_back("How to exploit vulnerabilities");
                
                return response;
            }
            
            // Default response for other queries
            output << "I'm not sure how to respond to that question. Here are some things I can help with:\n\n";
            output << "- Generate scripts for various purposes\n";
            output << "- Debug existing scripts\n";
            output << "- Explain Lua programming concepts\n";
            output << "- Scan games for vulnerabilities\n";
            output << "- Provide help and tutorials\n\n";
            
            output << "Could you rephrase your question or select one of these topics?";
            
            response.m_success = true;
            response.m_content = output.str();
            
            response.m_suggestions.push_back("Generate a script");
            response.m_suggestions.push_back("Debug a script");
            response.m_suggestions.push_back("Scan for vulnerabilities");
            
            return response;
        }
    } catch (const std::exception& e) {
        response.m_success = false;
        response.m_errorMessage = "Error in ProcessGeneralQuery: " + std::string(e.what());
        std::cerr << response.m_errorMessage << std::endl;
    }
    
    return response;
}

// Process request online
HybridAISystem::AIResponse HybridAISystem::ProcessRequestOnline(const AIRequest& request) {
    AIResponse response;
    
    // In a complete implementation, this would send the request to an online API
    // Since we're focusing on local training, we'll return a simulated failure
    // to force the system to use the local models
    
    response.m_success = false;
    response.m_errorMessage = "Online processing not available, using local models";
    
    return response;
}

// Check network connectivity
bool HybridAISystem::CheckNetworkConnectivity() {
    // In a real implementation, this would check for actual internet connectivity
    // For this example, we'll assume connectivity is available, but prefer local models
    return true;
}

// Load model
bool HybridAISystem::LoadModel(const std::string& modelName, int priority) {
    // Models are now created and trained locally, so we don't need to load them from files
    return true;
}

// Unload model
void HybridAISystem::UnloadModel(const std::string& modelName) {
    auto it = m_modelCache.find(modelName);
    if (it != m_modelCache.end()) {
        // Remove from cache
        m_modelCache.erase(it);
        
        // Remove from loaded models
        auto modelIt = std::find(m_loadedModelNames.begin(), m_loadedModelNames.end(), modelName);
        if (modelIt != m_loadedModelNames.end()) {
            m_loadedModelNames.erase(modelIt);
        }
    }
}

// Optimize memory usage
void HybridAISystem::OptimizeMemoryUsage() {
    // In a real implementation, this would use the priority of each model
    // to decide which to keep and which to unload
    
    // For this simplified version, we'll just ensure we're under the memory limit
    uint64_t currentMemory = GetMemoryUsage();
    if (currentMemory <= m_maxMemoryAllowed) {
        return;
    }
    
    // We need to free up some memory
    // Unload non-essential models
    std::vector<std::string> nonEssentialModels;
    
    for (const auto& name : m_loadedModelNames) {
        if (name != "script_generator" && name != "vulnerability_detector") {
            nonEssentialModels.push_back(name);
        }
    }
    
    // Unload models until we're under the limit
    for (const auto& name : nonEssentialModels) {
        UnloadModel(name);
        
        // Check if we're under the limit
        currentMemory = GetMemoryUsage();
        if (currentMemory <= m_maxMemoryAllowed) {
            break;
        }
    }
}

// Check if model is loaded
bool HybridAISystem::IsModelLoaded(const std::string& modelName) const {
    return m_modelCache.find(modelName) != m_modelCache.end();
}

// Get model
void* HybridAISystem::GetModel(const std::string& modelName) const {
    auto it = m_modelCache.find(modelName);
    if (it != m_modelCache.end()) {
        return it->second;
    }
    return nullptr;
}

// Generate script from template
std::string HybridAISystem::GenerateScriptFromTemplate(const std::string& templateName, 
                                                   const std::unordered_map<std::string, std::string>& parameters) {
    auto it = m_templateCache.find(templateName);
    if (it == m_templateCache.end()) {
        return "-- Template not found: " + templateName;
    }
    
    std::string script = it->second;
    
    // Replace parameters
    for (const auto& param : parameters) {
        std::string placeholder = "{{" + param.first + "}}";
        size_t pos = script.find(placeholder);
        while (pos != std::string::npos) {
            script.replace(pos, placeholder.length(), param.second);
            pos = script.find(placeholder, pos + param.second.length());
        }
    }
    
    return script;
}

// Load script templates
void HybridAISystem::LoadScriptTemplates() {
    // In a real implementation, these would be loaded from files
    // For this example, we'll define a few templates directly
    
    // ESP template
    m_templateCache["esp"] = R"(
-- ESP for all players
local players = game:GetService("Players")
local localPlayer = players.LocalPlayer
    
function createESP()
    for _, player in pairs(players:GetPlayers()) do
        if player ~= localPlayer and player.Character then
            -- Create ESP highlight
            local highlight = Instance.new("Highlight")
            highlight.FillColor = Color3.fromRGB({{r}}, {{g}}, {{b}})
            highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
            highlight.FillTransparency = {{transparency}}
            highlight.OutlineTransparency = 0
            highlight.Adornee = player.Character
            highlight.Parent = player.Character
            
            -- Add name label
            local billboardGui = Instance.new("BillboardGui")
            billboardGui.Size = UDim2.new(0, 100, 0, 40)
            billboardGui.AlwaysOnTop = true
            billboardGui.Parent = player.Character.Head
            
            local nameLabel = Instance.new("TextLabel")
            nameLabel.Size = UDim2.new(1, 0, 1, 0)
            nameLabel.BackgroundTransparency = 1
            nameLabel.TextColor3 = Color3.new(1, 1, 1)
            nameLabel.TextStrokeTransparency = 0
            nameLabel.Text = player.Name
            nameLabel.Parent = billboardGui
        end
    end
end

createESP()

-- Keep ESP updated with new players
players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function()
        wait(1) -- Wait for character to load
        createESP()
    end)
end)
)";
    
    // Speed hack template
    m_templateCache["speed"] = R"(
-- Speed hack
local speedMultiplier = {{speed}} -- Change this value to adjust speed

local players = game:GetService("Players")
local localPlayer = players.LocalPlayer
local userInputService = game:GetService("UserInputService")

-- Function to apply speed
local function applySpeed()
    if localPlayer.Character and localPlayer.Character:FindFirstChild("Humanoid") then
        localPlayer.Character.Humanoid.WalkSpeed = 16 * speedMultiplier
    end
end

-- Keep applying speed
game:GetService("RunService").Heartbeat:Connect(applySpeed)

-- Apply speed when character respawns
localPlayer.CharacterAdded:Connect(function(character)
    wait(0.5) -- Wait for humanoid to load
    applySpeed()
end)

-- Toggle with key press
local enabled = true
userInputService.InputBegan:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.{{toggle_key}} then
        enabled = not enabled
        speedMultiplier = enabled and {{speed}} or 1
        print("Speed hack " .. (enabled and "enabled" or "disabled"))
    end
end)

print("Speed hack loaded. Press {{toggle_key}} to toggle.")
)";
    
    // Aimbot template
    m_templateCache["aimbot"] = R"(
-- Aimbot
local players = game:GetService("Players")
local localPlayer = players.LocalPlayer
local userInputService = game:GetService("UserInputService")
local runService = game:GetService("RunService")
local camera = workspace.CurrentCamera

-- Settings
local settings = {
    enabled = true,
    aimKey = Enum.UserInputType.{{aim_key}}, -- Default: MouseButton2 (right mouse button)
    teamCheck = {{team_check}}, -- Don't target teammates
    wallCheck = {{wall_check}}, -- Check for walls
    maxDistance = {{max_distance}}, -- Maximum targeting distance
    smoothness = {{smoothness}}, -- Lower = faster (0.1 to 1)
    fovRadius = {{fov_radius}} -- Field of view limitation (pixels)
}

-- Function to check if a player is valid target
local function isValidTarget(player)
    if player == localPlayer then return false end
    if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then return false end
    if not player.Character:FindFirstChild("Humanoid") or player.Character.Humanoid.Health <= 0 then return false end
    
    -- Team check
    if settings.teamCheck and player.Team == localPlayer.Team then return false end
    
    -- Wall check
    if settings.wallCheck then
        local ray = Ray.new(camera.CFrame.Position, (player.Character.HumanoidRootPart.Position - camera.CFrame.Position).Unit * settings.maxDistance)
        local hit, position = workspace:FindPartOnRayWithIgnoreList(ray, {localPlayer.Character, camera})
        if hit and hit:IsDescendantOf(player.Character) then
            return true
        else
            return false
        end
    end
    
    return true
end

-- Function to get closest player
local function getClosestPlayer()
    local closestPlayer = nil
    local closestDistance = settings.maxDistance
    local mousePos = userInputService:GetMouseLocation()
    
    for _, player in pairs(players:GetPlayers()) do
        if isValidTarget(player) then
            local screenPos, onScreen = camera:WorldToScreenPoint(player.Character.HumanoidRootPart.Position)
            
            if onScreen then
                local distanceFromMouse = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                
                -- Check if within FOV
                if distanceFromMouse <= settings.fovRadius and distanceFromMouse < closestDistance then
                    closestPlayer = player
                    closestDistance = distanceFromMouse
                end
            end
        end
    end
    
    return closestPlayer
end

-- Main aimbot function
local isAiming = false
runService.RenderStepped:Connect(function()
    if settings.enabled and isAiming then
        local target = getClosestPlayer()
        
        if target then
            local targetPos = target.Character.HumanoidRootPart.Position
            
            -- Add head offset
            if target.Character:FindFirstChild("Head") then
                targetPos = target.Character.Head.Position
            end
            
            -- Create smooth aim
            local aimPos = camera.CFrame:Lerp(CFrame.new(camera.CFrame.Position, targetPos), settings.smoothness)
            camera.CFrame = aimPos
        end
    end
end)

-- Toggle aim on key press
userInputService.InputBegan:Connect(function(input)
    if input.UserInputType == settings.aimKey then
        isAiming = true
    end
end)

userInputService.InputEnded:Connect(function(input)
    if input.UserInputType == settings.aimKey then
        isAiming = false
    end
end)

-- Toggle aimbot with key press
userInputService.InputBegan:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.{{toggle_key}} then
        settings.enabled = not settings.enabled
        print("Aimbot " .. (settings.enabled and "enabled" or "disabled"))
    end
end)

print("Aimbot loaded. Hold right mouse button to aim. Press {{toggle_key}} to toggle.")
)";
}

// Get script templates
std::unordered_map<std::string, std::string> HybridAISystem::GetScriptTemplates() const {
    return m_templateCache;
}

// Store data persistently
bool HybridAISystem::StoreData(const std::string& key, const std::string& value) {
    m_dataStore[key] = value;
    return SaveToDataStore(key, value);
}

// Retrieve persistently stored data
std::string HybridAISystem::RetrieveData(const std::string& key, const std::string& defaultValue) {
    auto it = m_dataStore.find(key);
    if (it != m_dataStore.end()) {
        return it->second;
    }
    
    // Try to load from persistent storage
    std::string value = LoadFromDataStore(key, defaultValue);
    
    // Cache for future use
    if (value != defaultValue) {
        m_dataStore[key] = value;
    }
    
    return value;
}

// Save to data store
bool HybridAISystem::SaveToDataStore(const std::string& key, const std::string& value) {
    try {
        // Get Documents directory
        NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString* documentsDirectory = [paths objectAtIndex:0];
        
        // Create AIData directory if it doesn't exist
        NSString* aiDataDir = [documentsDirectory stringByAppendingPathComponent:@"AIData"];
        NSFileManager* fileManager = [NSFileManager defaultManager];
        
        if (![fileManager fileExistsAtPath:aiDataDir]) {
            NSError* error = nil;
            BOOL success = [fileManager createDirectoryAtPath:aiDataDir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:&error];
            if (!success) {
                std::cerr << "HybridAISystem: Failed to create AIData directory: " 
                         << [[error localizedDescription] UTF8String] << std::endl;
                return false;
            }
        }
        
        // Write value to file
        NSString* keyPath = [aiDataDir stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"%s.dat", key.c_str()]];
        
        NSData* data = [[NSString stringWithUTF8String:value.c_str()] dataUsingEncoding:NSUTF8StringEncoding];
        BOOL success = [data writeToFile:keyPath atomically:YES];
        
        return success;
    } catch (const std::exception& e) {
        std::cerr << "HybridAISystem: Exception during data store save: " << e.what() << std::endl;
        return false;
    }
}

// Load from data store
std::string HybridAISystem::LoadFromDataStore(const std::string& key, const std::string& defaultValue) {
    try {
        // Get Documents directory
        NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString* documentsDirectory = [paths objectAtIndex:0];
        
        // Check if AIData directory exists
        NSString* aiDataDir = [documentsDirectory stringByAppendingPathComponent:@"AIData"];
        NSFileManager* fileManager = [NSFileManager defaultManager];
        
        if (![fileManager fileExistsAtPath:aiDataDir]) {
            return defaultValue;
        }
        
        // Check if key file exists
        NSString* keyPath = [aiDataDir stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"%s.dat", key.c_str()]];
        
        if (![fileManager fileExistsAtPath:keyPath]) {
            return defaultValue;
        }
        
        // Read value from file
        NSData* data = [NSData dataWithContentsOfFile:keyPath];
        if (!data) {
            return defaultValue;
        }
        
        NSString* value = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        return [value UTF8String];
    } catch (const std::exception& e) {
        std::cerr << "HybridAISystem: Exception during data store load: " << e.what() << std::endl;
        return defaultValue;
    }
}

} // namespace AIFeatures
} // namespace iOS
