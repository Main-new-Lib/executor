#include "../../ios_compat.h"
#include "OfflineAISystem.h"
#include "local_models/LocalModelBase.h"
#include "local_models/ScriptGenerationModel.h"
#include "vulnerability_detection/VulnerabilityDetector.h"
#include <iostream>
#include <sstream>
#include <thread>
#include <regex>
#include <set>

namespace iOS {
namespace AIFeatures {

// Constructor
OfflineAISystem::OfflineAISystem()
    : m_initialized(false),
      m_modelsLoaded(false),
      m_isInLowMemoryMode(false),
      m_scriptAssistantModel(nullptr),
      m_scriptGeneratorModel(nullptr),
      m_debugAnalyzerModel(nullptr),
      m_patternRecognitionModel(nullptr),
      m_totalMemoryUsage(0),
      m_maxMemoryAllowed(200 * 1024 * 1024), // 200MB default
      m_responseCallback(nullptr) {
}

// Destructor
OfflineAISystem::~OfflineAISystem() {
    // Clean up resources
    for (const auto& pair : m_modelCache) {
        // Nothing to do here with our locally trained models
    }
}

// Initialize the AI system
bool OfflineAISystem::Initialize(const std::string& modelPath, std::function<void(float)> progressCallback) {
    if (m_initialized) {
        return true;
    }
    
    try {
        m_modelPath = modelPath;
        
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
                std::cerr << "OfflineAISystem: Failed to create models directory: " 
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
            m_modelCache["script_generator"] = scriptGenerator.get();
            m_loadedModelNames.push_back("script_generator");
        } else {
            std::cerr << "OfflineAISystem: Failed to initialize script generator model" << std::endl;
        }
        
        if (progressCallback) progressCallback(0.3f);
        
        // Initialize Vulnerability Detector
        auto vulnerabilityDetector = std::make_shared<VulnerabilityDetection::VulnerabilityDetector>();
        bool vulnerabilityInitialized = vulnerabilityDetector->Initialize(modelPath + "/vulnerability_detector");
        
        if (vulnerabilityInitialized) {
            m_patternRecognitionModel = vulnerabilityDetector.get();
            m_modelCache["vulnerability_detector"] = vulnerabilityDetector.get();
            m_loadedModelNames.push_back("vulnerability_detector");
        } else {
            std::cerr << "OfflineAISystem: Failed to initialize vulnerability detector" << std::endl;
        }
        
        if (progressCallback) progressCallback(0.5f);
        
        // Initialize Script Debugging model
        // In this implementation, we'll reuse the script generator for debugging
        if (scriptGenInitialized) {
            m_debugAnalyzerModel = scriptGenerator.get();
        }
        
        if (progressCallback) progressCallback(0.7f);
        
        // Load script templates
        LoadScriptTemplates();
        
        if (progressCallback) progressCallback(0.9f);
        
        m_initialized = true;
        m_modelsLoaded = true;
        
        if (progressCallback) progressCallback(1.0f);
        
        std::cout << "OfflineAISystem: Successfully initialized" << std::endl;
        return true;
    } catch (const std::exception& e) {
        std::cerr << "OfflineAISystem: Exception during initialization: " << e.what() << std::endl;
        return false;
    }
}

// Process a request
void OfflineAISystem::ProcessRequest(const AIRequest& request, ResponseCallback callback) {
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
OfflineAISystem::AIResponse OfflineAISystem::ProcessRequestSync(const AIRequest& request) {
    AIResponse response;
    
    // Check if initialized
    if (!m_initialized) {
        response.m_success = false;
        response.m_errorMessage = "AI system not initialized";
        return response;
    }
    
    // Start timing
    auto startTime = std::chrono::high_resolution_clock::now();
    
    // Process request based on type
    if (request.m_requestType == "script_generation") {
        response = ProcessScriptGeneration(request);
    } else if (request.m_requestType == "debug") {
        response = ProcessScriptDebugging(request);
    } else {
        // General query
        response = ProcessGeneralQuery(request);
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
void OfflineAISystem::GenerateScript(const std::string& description, const std::string& context, 
                               std::function<void(const std::string&)> callback) {
    if (!callback) {
        return;
    }
    
    // Create request
    AIRequest request(description, context, "script_generation");
    
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
void OfflineAISystem::DebugScript(const std::string& script, 
                            std::function<void(const std::string&)> callback) {
    if (!callback) {
        return;
    }
    
    // Create request
    AIRequest request("Debug this script", script, "debug");
    
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
OfflineAISystem::AIResponse OfflineAISystem::ProcessGeneralQuery(const AIRequest& request) {
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

// Handle memory warning
void OfflineAISystem::HandleMemoryWarning() {
    std::cout << "OfflineAISystem: Handling memory warning" << std::endl;
    
    // Set low memory mode
    m_isInLowMemoryMode = true;
    
    // Optimize memory usage
    OptimizeMemoryUsage();
}

// Check if the AI system is initialized
bool OfflineAISystem::IsInitialized() const {
    return m_initialized;
}

// Check if models are loaded
bool OfflineAISystem::AreModelsLoaded() const {
    return m_modelsLoaded;
}

// Get memory usage
uint64_t OfflineAISystem::GetMemoryUsage() const {
    return m_totalMemoryUsage;
}

// Set maximum allowed memory
void OfflineAISystem::SetMaxMemory(uint64_t maxMemory) {
    m_maxMemoryAllowed = maxMemory;
}

// Get loaded model names
std::vector<std::string> OfflineAISystem::GetLoadedModelNames() const {
    return m_loadedModelNames;
}

// Process script generation
OfflineAISystem::AIResponse OfflineAISystem::ProcessScriptGeneration(const AIRequest& request) {
    AIResponse response;
    
    try {
        // Check if script generator is available
        if (!m_scriptGeneratorModel) {
            response.m_success = false;
            response.m_errorMessage = "Script generator model not available";
            return response;
        }
        
        // Use the script generation model
        auto scriptGenerator = static_cast<LocalModels::ScriptGenerationModel*>(m_scriptGeneratorModel);
        LocalModels::ScriptGenerationModel::GeneratedScript generatedScript = 
            scriptGenerator->GenerateScript(request.m_query);
        
        // Set response
        response.m_success = true;
        response.m_content = "Script generated successfully";
        response.m_scriptCode = generatedScript.m_code;
        
        // Add suggestions
        response.m_suggestions.push_back("Execute script");
        response.m_suggestions.push_back("Edit script");
        response.m_suggestions.push_back("Save script");
        
        return response;
    } catch (const std::exception& e) {
        response.m_success = false;
        response.m_errorMessage = "Error generating script: " + std::string(e.what());
        return response;
    }
}

// Process script debugging
OfflineAISystem::AIResponse OfflineAISystem::ProcessScriptDebugging(const AIRequest& request) {
    AIResponse response;
    
    try {
        // Script to debug should be in the context
        std::string script = request.m_context;
        
        if (script.empty()) {
            response.m_success = false;
            response.m_errorMessage = "No script provided for debugging";
            return response;
        }
        
        // In a real implementation, this would use ML to analyze the script
        // For this example, we'll use rule-based debugging
        
        std::stringstream output;
        output << "# Script Analysis\n\n";
        
        // Check for common errors
        bool hasErrors = false;
        
        // Check for missing 'end' statements
        int openBlocks = 0;
        int closedBlocks = 0;
        
        std::regex openRegex("\\b(function|if|for|while|repeat|do)\\b");
        std::regex closeRegex("\\bend\\b");
        
        auto words_begin = std::sregex_iterator(script.begin(), script.end(), openRegex);
        auto words_end = std::sregex_iterator();
        
        for (std::sregex_iterator i = words_begin; i != words_end; ++i) {
            openBlocks++;
        }
        
        words_begin = std::sregex_iterator(script.begin(), script.end(), closeRegex);
        
        for (std::sregex_iterator i = words_begin; i != words_end; ++i) {
            closedBlocks++;
        }
        
        if (openBlocks > closedBlocks) {
            hasErrors = true;
            output << "- **Error**: Missing " << (openBlocks - closedBlocks) << " 'end' statement(s)\n";
        } else if (closedBlocks > openBlocks) {
            hasErrors = true;
            output << "- **Error**: Extra " << (closedBlocks - openBlocks) << " 'end' statement(s)\n";
        }
        
        // Check for undefined variables (simple check)
        std::regex localRegex("\\blocal\\s+([a-zA-Z0-9_]+)\\b");
        std::regex varRegex("\\b([a-zA-Z][a-zA-Z0-9_]*)\\s*=");
        std::regex useRegex("\\b([a-zA-Z][a-zA-Z0-9_]*)\\b");
        
        // Define variable sets before using them
        std::set<std::string> definedVars;
        std::set<std::string> usedVars;
        std::set<std::string> builtinVars = {
            "game", "workspace", "script", "table", "string", "math", "coroutine", "Enum",
            "Vector3", "Vector2", "CFrame", "Color3", "BrickColor", "Ray", "TweenInfo", "UDim2",
            "Instance", "player", "players", "true", "false", "nil", "function", "end", "if", "then",
            "else", "elseif", "for", "in", "pairs", "ipairs", "while", "do", "repeat", "until", "break",
            "return", "local", "and", "or", "not"
        };
        
        words_begin = std::sregex_iterator(script.begin(), script.end(), localRegex);
        
        for (std::sregex_iterator i = words_begin; i != words_end; ++i) {
            std::smatch match = *i;
            definedVars.insert(match[1]);
        }
        
        words_begin = std::sregex_iterator(script.begin(), script.end(), varRegex);
        
        for (std::sregex_iterator i = words_begin; i != words_end; ++i) {
            std::smatch match = *i;
            definedVars.insert(match[1]);
        }
        
        words_begin = std::sregex_iterator(script.begin(), script.end(), useRegex);
        
        for (std::sregex_iterator i = words_begin; i != words_end; ++i) {
            std::smatch match = *i;
            std::string var = match[1];
            if (builtinVars.find(var) == builtinVars.end()) {
                usedVars.insert(var);
            }
        }
        
        // Find undefined variables
        std::vector<std::string> undefinedVars;
        for (const auto& var : usedVars) {
            // Check if this variable is defined
            auto it = definedVars.find(var);
            if (it == definedVars.end()) {
                undefinedVars.push_back(var);
            }
        }
        
        if (!undefinedVars.empty()) {
            hasErrors = true;
            output << "- **Warning**: Potentially undefined variables:\n";
            for (const auto& var : undefinedVars) {
                output << "  - `" << var << "`\n";
            }
        }
        
        // Check for other common issues
        if (script.find("while true do") != std::string::npos && 
            script.find("wait") == std::string::npos) {
            hasErrors = true;
            output << "- **Warning**: Infinite loop detected (while true without wait)\n";
        }
        
        if (script.find("print") != std::string::npos) {
            output << "- **Note**: Script contains debug print statements\n";
        }
        
        // Add overall assessment
        if (hasErrors) {
            output << "\n## Issues Found\n\n";
            output << "The script has some issues that should be fixed before execution.\n";
        } else {
            output << "\n## No Major Issues\n\n";
            output << "The script looks good and should run without errors.\n";
        }
        
        // Add optimization suggestions
        output << "\n## Optimization Suggestions\n\n";
        
        if (script.find("for i = 1,") != std::string::npos) {
            output << "- Consider caching loop end values: `local max = table.length(t); for i = 1, max do`\n";
        }
        
        if (script.find("FindFirstChild") != std::string::npos) {
            output << "- Cache results of FindFirstChild calls for repeated access\n";
        }
        
        // Set response
        response.m_success = true;
        response.m_content = output.str();
        
        return response;
    } catch (const std::exception& e) {
        response.m_success = false;
        response.m_errorMessage = "Error debugging script: " + std::string(e.what());
        return response;
    }
}

// Process general query
OfflineAISystem::AIResponse OfflineAISystem::ProcessGeneralQuery(const AIRequest& request) {
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

// Load model
bool OfflineAISystem::LoadModel(const std::string& modelName, int priority) {
    // Models are now created and trained locally, so we don't need to load them from files
    return true;
}

// Unload model
void OfflineAISystem::UnloadModel(const std::string& modelName) {
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
void OfflineAISystem::OptimizeMemoryUsage() {
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
bool OfflineAISystem::IsModelLoaded(const std::string& modelName) const {
    return m_modelCache.find(modelName) != m_modelCache.end();
}

// Get model
void* OfflineAISystem::GetModel(const std::string& modelName) const {
    auto it = m_modelCache.find(modelName);
    if (it != m_modelCache.end()) {
        // Direct access to pointer instead of using get() since we're storing raw pointers now
        return it->second;
    }
    return nullptr;
}

// Load script templates
void OfflineAISystem::LoadScriptTemplates() {
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
            highlight.FillColor = Color3.fromRGB(255, 0, 0)
            highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
            highlight.FillTransparency = 0.5
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
local speedMultiplier = 3 -- Change this value to adjust speed

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
    if input.KeyCode == Enum.KeyCode.X then
        enabled = not enabled
        speedMultiplier = enabled and 3 or 1
        print("Speed hack " .. (enabled and "enabled" or "disabled"))
    end
end)

print("Speed hack loaded. Press X to toggle.")
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
    aimKey = Enum.UserInputType.MouseButton2, -- Right mouse button
    teamCheck = true, -- Don't target teammates
    wallCheck = true, -- Check for walls
    maxDistance = 500, -- Maximum targeting distance
    smoothness = 0.5, -- Lower = faster (0.1 to 1)
    fovRadius = 250 -- Field of view limitation (pixels)
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
    if input.KeyCode == Enum.KeyCode.Y then
        settings.enabled = not settings.enabled
        print("Aimbot " .. (settings.enabled and "enabled" or "disabled"))
    end
end)

print("Aimbot loaded. Hold right mouse button to aim. Press Y to toggle.")
)";
}

// Get script templates
std::unordered_map<std::string, std::string> OfflineAISystem::GetScriptTemplates() const {
    return m_scriptTemplates;
}

// Note: Primary LoadScriptTemplates implementation is already defined above

// Get template cache
std::unordered_map<std::string, std::string> OfflineAISystem::GetTemplateCache() const {
    return m_templateCache;
}

// Generate protection strategy
std::string OfflineAISystem::GenerateProtectionStrategy(const std::string& detectionType, 
                                         const std::vector<uint8_t>& signature) {
    // In a real implementation, this would generate a strategy to bypass detection
    // For this example, we'll return a simple strategy
    
    std::stringstream strategy;
    strategy << "-- Protection strategy for " << detectionType << "\n";
    strategy << "local function bypass()\n";
    strategy << "    -- Dynamic signature obfuscation\n";
    strategy << "    local original = {";
    
    // Add signature bytes
    for (size_t i = 0; i < std::min<size_t>(signature.size(), 16); ++i) {
        strategy << (int)signature[i];
        if (i < std::min<size_t>(signature.size(), 16) - 1) {
            strategy << ", ";
        }
    }
    
    strategy << "}\n";
    strategy << "    local modified = {}\n";
    strategy << "    for i, byte in ipairs(original) do\n";
    strategy << "        modified[i] = bit32.bxor(byte, 0x" << std::hex << (signature.size() % 256) << ")\n";
    strategy << "    end\n";
    strategy << "    \n";
    strategy << "    -- Apply protection\n";
    strategy << "    hookmetamethod(game, \"__namecall\", function(self, ...)\n";
    strategy << "        local method = getnamecallmethod()\n";
    strategy << "        if method == \"" << detectionType << "\" then\n";
    strategy << "            return nil\n";
    strategy << "        end\n";
    strategy << "        return original(self, ...)\n";
    strategy << "    end)\n";
    strategy << "end\n";
    strategy << "\n";
    strategy << "bypass()\n";
    
    return strategy.str();
}

} // namespace AIFeatures
} // namespace iOS
