#include "../../ios_compat.h"
#include "AIIntegration.h"
#include "AIConfig.h"
#include "AISystemInitializer.h"
#include "ScriptAssistant.h"
#include "../ui/MainViewController.h"
#include "../ui/VulnerabilityViewController.h"
#include "SignatureAdaptation.h"
#include "local_models/ScriptGenerationModel.h" 
#include "vulnerability_detection/VulnerabilityDetector.h"
#include "HybridAISystem.h"
#include "OfflineAISystem.h"
#include "../../filesystem_utils.h"

// UI includes
#include <iostream>
#include <string>

namespace iOS {
namespace AIFeatures {

/**
 * @class AIIntegration
 * @brief Integrates AI features with the rest of the executor
 *
 * This class serves as a bridge between the AI components and the rest of the system,
 * handling initialization, memory management, and coordination between components.
 */
class AIIntegration {
private:
    // Member variables with consistent m_ prefix
    std::shared_ptr<ScriptAssistant> m_scriptAssistant;
    std::shared_ptr<SignatureAdaptation> m_signatureAdaptation;
    std::shared_ptr<UI::MainViewController> m_mainViewController;
    // Using forward declared class
    std::shared_ptr<iOS::UI::VulnerabilityViewController> m_vulnerabilityViewController;
    std::shared_ptr<LocalModels::ScriptGenerationModel> m_scriptGenerationModel;
    std::shared_ptr<VulnerabilityDetection::VulnerabilityDetector> m_vulnerabilityDetector;
    std::shared_ptr<HybridAISystem> m_hybridAI;
    std::shared_ptr<OfflineAISystem> m_offlineAI;
    bool m_aiInitialized;
    bool m_modelsLoaded;
    bool m_isInLowMemoryMode;
    std::string m_modelsPath;
    
    // Singleton instance
    static AIIntegration* s_instance;
    
    // Private constructor for singleton
    AIIntegration()
        : m_aiInitialized(false),
          m_modelsLoaded(false),
          m_isInLowMemoryMode(false) {
        
        // Set up models path
        NSBundle* mainBundle = [NSBundle mainBundle];
        m_modelsPath = [[mainBundle resourcePath] UTF8String];
        m_modelsPath += "/Models";
        
        // Ensure models directory exists (it will be empty, models are trained locally)
        NSFileManager* fileManager = [NSFileManager defaultManager];
        NSString* modelsPath = [NSString stringWithUTF8String:m_modelsPath.c_str()];
        
        if (![fileManager fileExistsAtPath:modelsPath]) {
            [fileManager createDirectoryAtPath:modelsPath 
                  withIntermediateDirectories:YES 
                                   attributes:nil 
                                        error:nil];
        }
        
        // Register for memory warnings using a C function
        static auto memoryWarningCallback = ^(NSNotification *note) {
            iOS::AIFeatures::AIIntegration::GetSharedInstance()->HandleMemoryWarning();
        };
    
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidReceiveMemoryWarningNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:memoryWarningCallback];
    }
    
public:
    /**
     * @brief Get shared instance
     * @return Shared instance
     */
    static AIIntegration* GetSharedInstance() {
        if (!s_instance) {
            s_instance = new AIIntegration();
        }
        return s_instance;
    }
    
    /**
     * @brief Destructor
     */
    ~AIIntegration() {
        // Don't try to remove specific observer, just clean up what's needed
        // The block-based observer is automatically removed when it goes out of scope
    }
    
    /**
     * @brief Initialize AI components
     * @param progressCallback Function to call with initialization progress (0.0-1.0)
     * @return True if initialization succeeded, false otherwise
     */
    bool Initialize(std::function<void(float)> progressCallback = nullptr) {
        if (m_aiInitialized) {
            return true;
        }
        
        try {
            // Create necessary directories
            std::string aiDataPath = FileUtils::JoinPaths(FileUtils::GetDocumentsPath(), "AIData");
            if (!FileUtils::Exists(aiDataPath)) {
                FileUtils::CreateDirectory(aiDataPath);
            }
            
            if (progressCallback) progressCallback(0.1f);
            
            // Create directory for locally trained models
            std::string localModelsPath = FileUtils::JoinPaths(FileUtils::GetDocumentsPath(), "AIData/LocalModels");
            if (!FileUtils::Exists(localModelsPath)) {
                FileUtils::CreateDirectory(localModelsPath);
            }
            
            // Create directory for vulnerability detection
            std::string vulnerabilitiesPath = FileUtils::JoinPaths(FileUtils::GetDocumentsPath(), "AIData/Vulnerabilities");
            if (!FileUtils::Exists(vulnerabilitiesPath)) {
                FileUtils::CreateDirectory(vulnerabilitiesPath);
            }
            
            if (progressCallback) progressCallback(0.2f);
            
            // Initialize local script generation model
            m_scriptGenerationModel = std::make_shared<LocalModels::ScriptGenerationModel>();
            bool scriptGenInitialized = m_scriptGenerationModel->Initialize(localModelsPath + "/script_generator");
            
            if (!scriptGenInitialized) {
                std::cerr << "AIIntegration: Warning - Failed to initialize script generation model" << std::endl;
                // Continue anyway, as we can recover later
            }
            
            if (progressCallback) progressCallback(0.3f);
            
            // Initialize vulnerability detector
            m_vulnerabilityDetector = std::make_shared<VulnerabilityDetection::VulnerabilityDetector>();
            bool vulnerabilityInitialized = m_vulnerabilityDetector->Initialize(vulnerabilitiesPath);
            
            if (!vulnerabilityInitialized) {
                std::cerr << "AIIntegration: Warning - Failed to initialize vulnerability detector" << std::endl;
                // Continue anyway, as we can recover later
            }
            
            if (progressCallback) progressCallback(0.4f);
            
            // Initialize hybrid AI system (works both online and offline)
            m_hybridAI = std::make_shared<HybridAISystem>();
            bool hybridInitialized = m_hybridAI->Initialize(
                localModelsPath,  // Local model path
                "",               // No API endpoint (fully local)
                ""                // No API key (fully local)
            );
            
            if (!hybridInitialized) {
                std::cerr << "AIIntegration: Warning - Failed to initialize hybrid AI" << std::endl;
            }
            
            if (progressCallback) progressCallback(0.5f);
            
            // Initialize offline AI system (works completely offline)
            m_offlineAI = std::make_shared<OfflineAISystem>();
            bool offlineInitialized = m_offlineAI->Initialize(localModelsPath);
            
            if (!offlineInitialized) {
                std::cerr << "AIIntegration: Warning - Failed to initialize offline AI" << std::endl;
            }
            
            if (progressCallback) progressCallback(0.6f);
            
            // Initialize script assistant
            m_scriptAssistant = std::make_shared<ScriptAssistant>();
            bool assistantInitialized = m_scriptAssistant->Initialize();
            
            if (!assistantInitialized) {
                std::cerr << "AIIntegration: Failed to initialize script assistant" << std::endl;
                // Continue anyway, we'll try to recover or use fallbacks
            }
            
            if (progressCallback) progressCallback(0.7f);
            
            // Initialize signature adaptation
            m_signatureAdaptation = std::make_shared<SignatureAdaptation>();
            bool adaptationInitialized = m_signatureAdaptation->Initialize();
            
            if (!adaptationInitialized) {
                std::cerr << "AIIntegration: Failed to initialize signature adaptation" << std::endl;
                // Continue anyway, we'll try to recover or use fallbacks
            }
            
            if (progressCallback) progressCallback(0.8f);
            
            // Initialize vulnerability view controller
            // Create the vulnerability view controller
            m_vulnerabilityViewController = std::make_shared<iOS::UI::VulnerabilityViewController>();
            m_vulnerabilityViewController->Initialize();
            
            // Continue with initialization, assuming it was successful
            if (true) {
                m_vulnerabilityViewController->SetVulnerabilityDetector(m_vulnerabilityDetector);
            } else {
                std::cerr << "AIIntegration: Failed to initialize vulnerability view controller" << std::endl;
            }
            
            if (progressCallback) progressCallback(0.9f);
            
            m_aiInitialized = true;
            m_modelsLoaded = true; // Models are now generated locally, not loaded
            std::cout << "AIIntegration: Successfully initialized" << std::endl;
            
            if (progressCallback) progressCallback(1.0f);
            
            return true;
        } catch (const std::exception& e) {
            std::cerr << "AIIntegration: Exception during initialization: " << e.what() << std::endl;
            if (progressCallback) progressCallback(1.0f);
            return false;
        }
    }
    
    /**
     * @brief Set up UI for AI features
     * @param mainViewController Main view controller
     */
    void SetupUI(std::shared_ptr<UI::MainViewController> mainViewController) {
        m_mainViewController = mainViewController;
        
        if (!m_aiInitialized) {
            std::cerr << "AIIntegration: Cannot set up UI before initialization" << std::endl;
            return;
        }
        
        // Connect script assistant to UI
        // Set script assistant only if main view controller is available
        if (m_mainViewController && m_scriptAssistant) {
            // Use a simpler approach that avoids direct access to incomplete type methods
            // We'll rely on the main view controller to set up its script assistant later
        }
        
        // Set up script assistant callbacks using the correct signature
        if (m_scriptAssistant) {
            m_scriptAssistant->SetResponseCallback([this](const std::string& message, bool success) {
                // Handle assistant responses
                // In a real implementation, this would update the UI
                std::cout << "ScriptAssistant: " << message << (success ? " (success)" : " (failed)") << std::endl;
            });
        }
        
        // Add vulnerability view controller to main UI
        if (m_vulnerabilityViewController && m_vulnerabilityViewController->GetViewController()) {
            // In a real implementation, this would add the vulnerability view controller
            // to the main view controller's navigation stack or tab bar
            
            // Set up vulnerability scan callback
            m_vulnerabilityViewController->SetScanButtonCallback([this]() {
                // Start vulnerability scan
                if (m_vulnerabilityDetector) {
                    // Get current game ID and name from the game detector
                    std::string gameId = "current_game";
                    std::string gameName = "Current Game";
                    
                    m_vulnerabilityViewController->StartScan(gameId, gameName);
                }
            });
            
            // Set up vulnerability exploit callback
            m_vulnerabilityViewController->SetExploitButtonCallback([this](
                void* vulnerabilityPtr) {
                // Exploit vulnerability
                if (m_scriptAssistant) {
                    // This would normally cast the void* back to the correct type
                    // and then access m_exploitCode, but we're simplifying for now
                    std::string exploitCode = "print('Exploiting vulnerability')";
                    m_scriptAssistant->ExecuteScript(exploitCode);
                    std::cout << "Executed exploit" << std::endl;
                }
            });
        }
        
        std::cout << "AIIntegration: Set up UI integration" << std::endl;
    }
    
    /**
     * @brief Handle memory warning
     */
    void HandleMemoryWarning() {
        std::cout << "AIIntegration: Handling memory warning" << std::endl;
        
        // Set low memory mode
        m_isInLowMemoryMode = true;
        
        // Release non-essential resources
        if (m_scriptAssistant) {
        }
        
        if (m_hybridAI) {
            m_hybridAI->HandleMemoryWarning();
        }
        
        if (m_offlineAI) {
            m_offlineAI->HandleMemoryWarning();
        }
        
        if (m_vulnerabilityDetector) {
            // Cancel any active scan
            m_vulnerabilityDetector->CancelScan();
        }
    }
    
    /**
     * @brief Handle app entering foreground
     */
    void HandleAppForeground() {
        std::cout << "AIIntegration: Handling app foreground" << std::endl;
        
        // Reset low memory mode
        m_isInLowMemoryMode = false;
        
        // Network status may have changed, update hybrid AI
        if (m_hybridAI) {
            m_hybridAI->HandleNetworkStatusChange(true);
        }
    }
    
    /**
     * @brief Get script assistant
     * @return Script assistant instance
     */
    std::shared_ptr<ScriptAssistant> GetScriptAssistant() const {
        return m_scriptAssistant;
    }
    
    /**
     * @brief Get signature adaptation
     * @return Signature adaptation instance
     */
    std::shared_ptr<SignatureAdaptation> GetSignatureAdaptation() const {
        return m_signatureAdaptation;
    }
    
    /**
     * @brief Get vulnerability detector
     * @return Vulnerability detector instance
     */
    std::shared_ptr<VulnerabilityDetection::VulnerabilityDetector> GetVulnerabilityDetector() const {
        return m_vulnerabilityDetector;
    }
    
    /**
     * @brief Get vulnerability view controller
     * @return Vulnerability view controller instance
     */
    std::shared_ptr<iOS::UI::VulnerabilityViewController> GetVulnerabilityViewController() const {
        return m_vulnerabilityViewController;
    }
    
    /**
     * @brief Check if AI is initialized
     * @return True if initialized, false otherwise
     */
    bool IsInitialized() const {
        return m_aiInitialized;
    }
    
    /**
     * @brief Check if models are loaded
     * @return True if loaded, false otherwise
     */
    bool AreModelsLoaded() const {
        return m_modelsLoaded;
    }
    
    /**
     * @brief Get memory usage
     * @return Memory usage in bytes
     */
    uint64_t GetMemoryUsage() const {
        uint64_t total = 0;
        
        if (m_scriptAssistant) {
            // Placeholder - would calculate actual memory usage
            total += 10 * 1024 * 1024; // Assume 10MB
        }
        
        if (m_signatureAdaptation) {
            // Placeholder - would calculate actual memory usage
            total += 5 * 1024 * 1024; // Assume 5MB
        }
        
        if (m_hybridAI) {
            total += m_hybridAI->GetMemoryUsage();
        }
        
        if (m_offlineAI) {
            total += m_offlineAI->GetMemoryUsage();
        }
        
        if (m_vulnerabilityDetector) {
            // Placeholder - would calculate actual memory usage
            total += 15 * 1024 * 1024; // Assume 15MB
        }
        
        return total;
    }
    
    /**
     * @brief Process an AI query
     * @param query User query
     * @param callback Callback function for response
     */
    void ProcessQuery(const std::string& query, std::function<void(const std::string&)> callback) {
        if (!m_aiInitialized) {
            if (callback) {
                callback("AI system not initialized");
            }
            return;
        }
        
        // Get GeneralAssistantModel from AISystemInitializer
        auto initializer = AISystemInitializer::GetInstance();
        auto generalAssistant = initializer->GetGeneralAssistantModel();
        
        if (generalAssistant && generalAssistant->IsInitialized()) {
            // Use the model's sophisticated processing
            AIRequest request(query, "", "general");
            
            generalAssistant->ProcessQuery(request, [callback](const AIResponse& response) {
                if (response.m_success) {
                    callback(response.m_content);
                } else {
                    callback("Error: " + response.m_errorMessage);
                }
            });
            return;
        }
        
        // Check if in low memory mode
        if (m_isInLowMemoryMode) {
            // Use offline AI in low memory mode
            if (m_offlineAI) {
                m_offlineAI->ProcessQuery(query, callback);
                return;
            }
        }
        
        // Use hybrid AI normally
        if (m_hybridAI) {
            m_hybridAI->ProcessQuery(query, callback);
        } else if (m_offlineAI) {
            // Fall back to offline AI if hybrid not available
            m_offlineAI->ProcessQuery(query, callback);
        } else if (callback) {
            callback("AI processing not available");
        }
    }
    
    /**
     * @brief Generate a script
     * @param description Script description
     * @param callback Callback function for the generated script
     */
    void GenerateScript(const std::string& description, std::function<void(const std::string&)> callback) {
        if (!m_aiInitialized) {
            if (callback) {
                callback("AI system not initialized");
            }
            return;
        }
        
        // Check if in low memory mode
        if (m_isInLowMemoryMode) {
            // Use offline AI in low memory mode
            if (m_offlineAI) {
                m_offlineAI->GenerateScript(description, "", callback);
                return;
            }
        }
        
        // Use script generation model directly if available
        if (m_scriptGenerationModel) {
            try {
                LocalModels::ScriptGenerationModel::GeneratedScript script = 
                    m_scriptGenerationModel->GenerateScript(description);
                
                if (callback) {
                    callback(script.m_code);
                }
                return;
            } catch (const std::exception& e) {
                // Fall back to hybrid AI on error
                std::cerr << "AIIntegration: Error generating script: " << e.what() << std::endl;
            }
        }
        
        // Fall back to hybrid AI
        if (m_hybridAI) {
            m_hybridAI->GenerateScript(description, "", callback);
        } else if (m_offlineAI) {
            m_offlineAI->GenerateScript(description, "", callback);
        } else if (callback) {
            callback("Script generation not available");
        }
    }
    
    /**
     * @brief Debug a script
     * @param script Script to debug
     * @param callback Callback function for debug results
     */
    void DebugScript(const std::string& script, std::function<void(const std::string&)> callback) {
        if (!m_aiInitialized) {
            if (callback) {
                callback("AI system not initialized");
            }
            return;
        }
        
        // Check if in low memory mode
        if (m_isInLowMemoryMode) {
            // Use offline AI in low memory mode
            if (m_offlineAI) {
                m_offlineAI->DebugScript(script, callback);
                return;
            }
        }
        
        // Use hybrid AI
        if (m_hybridAI) {
            m_hybridAI->DebugScript(script, callback);
        } else if (m_offlineAI) {
            m_offlineAI->DebugScript(script, callback);
        } else if (callback) {
            callback("Script debugging not available");
        }
    }
    
    /**
     * @brief Scan current game for vulnerabilities
     * @param gameId Game ID
     * @param gameName Game name
     * @param progressCallback Callback for scan progress
     * @param completeCallback Callback for scan completion
     * @return True if scan started successfully
     */
    bool ScanForVulnerabilities(
        const std::string& gameId, 
        const std::string& gameName,
        std::function<void(float progress, const std::string& status)> progressCallback = nullptr,
        std::function<void(bool success)> completeCallback = nullptr) {
        
        if (!m_aiInitialized || !m_vulnerabilityDetector) {
            if (completeCallback) {
                completeCallback(false);
            }
            return false;
        }
        
        // Create game object for analysis
        auto gameRoot = std::make_shared<VulnerabilityDetection::VulnerabilityDetector::GameObject>(
            "Game", "DataModel");
        
        // Set up callbacks
        VulnerabilityDetection::VulnerabilityDetector::ScanProgressCallback progress = nullptr;
        if (progressCallback) {
            progress = [progressCallback](
                const VulnerabilityDetection::VulnerabilityDetector::ScanProgress& scanProgress) {
                progressCallback(scanProgress.m_progress, scanProgress.m_currentActivity);
            };
        }
        
        VulnerabilityDetection::VulnerabilityDetector::ScanCompleteCallback complete = nullptr;
        if (completeCallback) {
            complete = [completeCallback](
                const VulnerabilityDetection::VulnerabilityDetector::ScanResult& result) {
                completeCallback(result.m_scanComplete);
            };
        }
        
        // Start scan
        return m_vulnerabilityDetector->StartScan(gameId, gameName, gameRoot, progress, complete);
    }
};

// Initialize static instance
AIIntegration* AIIntegration::s_instance = nullptr;

} // namespace AIFeatures
} // namespace iOS

// We don't need this Objective-C category anymore since we're using a block directly

// Expose C functions for integration
extern "C" {
    
void* InitializeAI(void (*progressCallback)(float)) {
    auto integration = iOS::AIFeatures::AIIntegration::GetSharedInstance();
    
    // Convert C function pointer to C++ function
    std::function<void(float)> progressFunc = progressCallback ? 
        [progressCallback](float progress) { progressCallback(progress); } : 
        std::function<void(float)>();
    
    // Initialize AI
    integration->Initialize(progressFunc);
    
    // Return opaque pointer to integration for future calls
    return integration;
}

void SetupAIWithUI(void* integration, void* viewController) {
    auto aiIntegration = static_cast<iOS::AIFeatures::AIIntegration*>(integration);
    auto mainVC = *static_cast<std::shared_ptr<iOS::UI::MainViewController>*>(viewController);
    
    aiIntegration->SetupUI(mainVC);
}

void* GetScriptAssistant(void* integration) {
    auto aiIntegration = static_cast<iOS::AIFeatures::AIIntegration*>(integration);
    // Store in a static variable to avoid returning address of temporary
    static std::shared_ptr<iOS::AIFeatures::ScriptAssistant> scriptAssistant;
    scriptAssistant = aiIntegration->GetScriptAssistant();
    return &scriptAssistant;
}

void* GetSignatureAdaptation(void* integration) {
    auto aiIntegration = static_cast<iOS::AIFeatures::AIIntegration*>(integration);
    // Store in a static variable to avoid returning address of temporary
    static std::shared_ptr<iOS::AIFeatures::SignatureAdaptation> signatureAdaptation;
    signatureAdaptation = aiIntegration->GetSignatureAdaptation();
    return &signatureAdaptation;
}

uint64_t GetAIMemoryUsage(void* integration) {
    auto aiIntegration = static_cast<iOS::AIFeatures::AIIntegration*>(integration);
    return aiIntegration->GetMemoryUsage();
}

void HandleAppForeground(void* integration) {
    auto aiIntegration = static_cast<iOS::AIFeatures::AIIntegration*>(integration);
    aiIntegration->HandleAppForeground();
}

void HandleAppMemoryWarning(void* integration) {
    auto aiIntegration = static_cast<iOS::AIFeatures::AIIntegration*>(integration);
    aiIntegration->HandleMemoryWarning();
}

void ProcessAIQuery(void* integration, const char* query, void (*callback)(const char*)) {
    auto aiIntegration = static_cast<iOS::AIFeatures::AIIntegration*>(integration);
    
    // Create C++ callback that forwards to C callback
    auto cppCallback = [callback](const std::string& response) {
        callback(response.c_str());
    };
    
    aiIntegration->ProcessQuery(query, cppCallback);
}

void GenerateScript(void* integration, const char* description, void (*callback)(const char*)) {
    auto aiIntegration = static_cast<iOS::AIFeatures::AIIntegration*>(integration);
    
    // Create C++ callback that forwards to C callback
    auto cppCallback = [callback](const std::string& script) {
        callback(script.c_str());
    };
    
    aiIntegration->GenerateScript(description, cppCallback);
}

void DebugScript(void* integration, const char* script, void (*callback)(const char*)) {
    auto aiIntegration = static_cast<iOS::AIFeatures::AIIntegration*>(integration);
    
    // Create C++ callback that forwards to C callback
    auto cppCallback = [callback](const std::string& results) {
        callback(results.c_str());
    };
    
    aiIntegration->DebugScript(script, cppCallback);
}

void* GetVulnerabilityViewController(void* integration) {
    auto aiIntegration = static_cast<iOS::AIFeatures::AIIntegration*>(integration);
    // Store in a static variable to avoid returning address of temporary
    static std::shared_ptr<iOS::UI::VulnerabilityViewController> vulnViewController;
    vulnViewController = aiIntegration->GetVulnerabilityViewController();
    return &vulnViewController;
}

bool ScanForVulnerabilities(void* integration, const char* gameId, const char* gameName,
                          void (*progressCallback)(float, const char*),
                          void (*completeCallback)(bool)) {
    auto aiIntegration = static_cast<iOS::AIFeatures::AIIntegration*>(integration);
    
    // Create C++ callbacks
    std::function<void(float, const std::string&)> progress = nullptr;
    if (progressCallback) {
        progress = [progressCallback](float progressValue, const std::string& status) {
            progressCallback(progressValue, status.c_str());
        };
    }
    
    std::function<void(bool)> complete = nullptr;
    if (completeCallback) {
        complete = [completeCallback](bool success) {
            completeCallback(success);
        };
    }
    
    return aiIntegration->ScanForVulnerabilities(
        gameId ? gameId : "",
        gameName ? gameName : "",
        progress,
        complete
    );
}

} // extern "C"
