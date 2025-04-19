#pragma once

#include "LocalModelBase.h"
#include <string>
#include <vector>
#include <unordered_map>
#include <memory>
#include <mutex>

namespace iOS {
namespace AIFeatures {

// Forward declarations for AIRequest and AIResponse structures
struct AIRequest;
struct AIResponse;

namespace LocalModels {

/**
 * @class GeneralAssistantModel
 * @brief AI assistant model for general user interaction
 * 
 * This model serves as a general-purpose assistant that helps users with
 * all aspects of the executor. It integrates with other AI models and
 * adapts to user behavior and preferences over time. The assistant provides
 * personalized responses based on user proficiency level and interaction history,
 * continuously improving its capabilities through self-learning.
 */
class GeneralAssistantModel : public ::iOS::AIFeatures::LocalModels::LocalModelBase {
public:
    // Message type enumeration
    enum class MessageType {
        System,         // System message (internal context)
        User,           // User message (user input)
        Assistant,      // Assistant response (model output)
        Tool            // Tool output (system events, actions)
    };
    
    // User proficiency level
    enum class UserProficiency {
        Beginner,       // New to scripting/exploiting (0-10 interactions)
        Intermediate,   // Some experience (11-30 interactions)
        Advanced,       // Experienced user (31-100 interactions)
        Expert          // Expert user with deep knowledge (100+ interactions)
    };
    
    // Interaction context
    struct Interaction {
        std::string m_content;    // Message content
        MessageType m_type;       // Message type
        uint64_t m_timestamp;     // Timestamp (microseconds since epoch)
        
        Interaction() : m_timestamp(0) {}
        
        Interaction(const std::string& content, MessageType type, uint64_t timestamp) 
            : m_content(content), m_type(type), m_timestamp(timestamp) {}
    };
    
    // User profile
    struct UserProfile {
        std::string m_userId;                  // User identifier
        UserProficiency m_proficiency;         // User proficiency
        std::vector<std::string> m_interests;  // User interests (script types, games)
        std::unordered_map<std::string, float> m_preferences; // Feature preferences
        uint64_t m_lastActive;                 // Last active timestamp
        uint32_t m_interactionCount;           // Number of interactions
        
        UserProfile() : m_proficiency(UserProficiency::Beginner), m_lastActive(0), m_interactionCount(0) {}
    };
    
private:
    // Private implementation
    UserProfile m_currentProfile;             // Current user profile
    std::vector<Interaction> m_interactionHistory; // Interaction history
    std::unordered_map<std::string, UserProfile> m_userProfiles; // Stored profiles
    
    bool m_isInitialized;                     // Whether model is initialized
    std::string m_storagePath;                // Path to model storage
    void* m_internalModel;                    // Pointer to internal model implementation
    mutable std::mutex m_mutex;               // Mutex for thread safety
    
    // Response generation context
    struct GenerationContext {
        UserProficiency proficiency;          // User proficiency
        std::vector<std::string> interests;   // User interests
        std::unordered_map<std::string, float> preferences; // User preferences
        std::vector<Interaction> recentInteractions; // Recent interactions
        
        GenerationContext() : proficiency(UserProficiency::Beginner) {}
    };
    
    // Private helper methods
    void UpdateUserProfile(const Interaction& interaction);
    void SaveUserProfiles();
    void LoadUserProfiles();
    void AdaptModelToUser(const UserProfile& profile);
    std::string GenerateContextAwareResponse(const std::string& input, const GenerationContext& context);
    std::vector<Interaction> GetRelevantInteractionHistory(size_t maxItems = 10) const;
    std::string DetectIntent(const std::string& input) const;
    std::string GetResponseForIntent(const std::string& intent, const GenerationContext& context) const;
    std::vector<std::string> ExtractEntities(const std::string& input) const;
    std::vector<std::string> FindRelevantTopics(const std::string& input) const;
    
public:
    /**
     * @brief Constructor
     */
    GeneralAssistantModel();
    
    /**
     * @brief Destructor
     */
    ~GeneralAssistantModel();
    
    /**
     * @brief Initialize the model
     * @param modelPath Path to model data
     * @return True if initialization is successful
     */
    bool Initialize(const std::string& modelPath);
    
    /**
     * @brief Process user input and generate a response
     * @param input User input
     * @param userId User identifier (optional)
     * @return Assistant response
     */
    std::string ProcessInput(const std::string& input, const std::string& userId = "");
    
    /**
     * @brief Process user input with system context
     * @param input User input
     * @param systemContext Additional context for the assistant
     * @param userId User identifier (optional)
     * @return Assistant response
     */
    std::string ProcessInputWithContext(const std::string& input, const std::string& systemContext, const std::string& userId = "");
    
    /**
     * @brief Process a query using the AI model
     * @param request The AI request containing query and context information
     * @return AI response with generated content and metadata
     */
    ::iOS::AIFeatures::AIResponse ProcessQuery(const ::iOS::AIFeatures::AIRequest& request);
    
    /**
     * @brief Process a query asynchronously using the AI model
     * @param request The AI request containing query and context information
     * @param callback Callback function to receive the response
     */
    void ProcessQuery(const ::iOS::AIFeatures::AIRequest& request, std::function<void(const ::iOS::AIFeatures::AIResponse&)> callback);
    
    /**
     * @brief Set current user
     * @param userId User identifier
     * @return True if user profile was loaded or created
     */
    bool SetCurrentUser(const std::string& userId);
    
    /**
     * @brief Add system message to context
     * @param message System message
     */
    void AddSystemMessage(const std::string& message);
    
    /**
     * @brief Add tool output to context
     * @param toolName Tool name
     * @param output Tool output
     */
    void AddToolOutput(const std::string& toolName, const std::string& output);
    
    /**
     * @brief Get user proficiency
     * @return User proficiency level
     */
    UserProficiency GetUserProficiency() const;
    
    /**
     * @brief Check if model is initialized
     * @return True if initialized
     */
    bool IsInitialized() const;
    
    /**
     * @brief Set model path
     * @param path Path to model files
     * @return True if path was valid and set
     */
    bool SetModelPath(const std::string& path);
    
    /**
     * @brief Reset conversation history
     * Resets user conversation while preserving system context
     */
    void ResetConversation();
    
    /**
     * @brief Get model version
     * @return Model version string
     */
    std::string GetVersion() const;
    
    /**
     * @brief Get memory usage in bytes
     * @return Memory usage
     */
    uint64_t GetMemoryUsage() const;
    
    /**
     * @brief Release unused memory resources
     */
    void ReleaseUnusedResources();
    
    /**
     * @brief Provide information about another AI model
     * @param modelName Model name
     * @param modelDescription Model description
     * @param modelCapabilities Model capabilities
     */
    void AddModelAwareness(const std::string& modelName, 
                          const std::string& modelDescription,
                          const std::vector<std::string>& modelCapabilities);
    
    /**
     * @brief Notify of executor feature usage
     * @param featureName Feature name
     * @param context Usage context
     */
    void NotifyFeatureUsage(const std::string& featureName, const std::string& context);
    
    /**
     * @brief Train the model on new data
     * @return True if training was successful
     */
    bool Train();
    
    /**
     * @brief Set user interests
     * @param interests User interests
     */
    void SetUserInterests(const std::vector<std::string>& interests);
    
    /**
     * @brief Get user interests
     * @return User interests
     */
    std::vector<std::string> GetUserInterests() const;
    
    /**
     * @brief Set user preference
     * @param preference Preference name
     * @param value Preference value (0.0-1.0)
     */
    void SetUserPreference(const std::string& preference, float value);
    
    /**
     * @brief Get user preference
     * @param preference Preference name
     * @param defaultValue Default value if preference not found
     * @return Preference value
     */
    float GetUserPreference(const std::string& preference, float defaultValue = 0.5f) const;
};

} // namespace LocalModels
} // namespace AIFeatures
} // namespace iOS
