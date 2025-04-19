#include "GeneralAssistantModel.h"
#include "../HybridAISystem.h" // For AIRequest and AIResponse structures
#include <chrono>
#include <iostream>
#include <algorithm>
#include <sstream>
#include <thread>
#include <regex> // Added for regex replacement

namespace iOS {
namespace AIFeatures {
namespace LocalModels {

// Implementation of ProcessQuery method
AIResponse GeneralAssistantModel::ProcessQuery(const AIRequest& request) {
    AIResponse response;
    
    // Check if model is initialized
    if (!IsInitialized()) {
        response.m_success = false;
        response.m_errorMessage = "GeneralAssistantModel is not initialized";
        return response;
    }
    
    // Start timing for performance measurement
    auto startTime = std::chrono::high_resolution_clock::now();
    
    try {
        // Lock for thread safety
        std::lock_guard<std::mutex> lock(m_mutex);
        
        // Extract user ID if available in context
        std::string userId = "";
        if (!request.m_context.empty()) {
            // Simple parsing to extract user ID from context
            // In a real implementation, this would be more sophisticated
            size_t userIdPos = request.m_context.find("user_id:");
            if (userIdPos != std::string::npos) {
                size_t startPos = userIdPos + 8; // Length of "user_id:"
                size_t endPos = request.m_context.find(";", startPos);
                if (endPos != std::string::npos) {
                    userId = request.m_context.substr(startPos, endPos - startPos);
                }
            }
        }
        
        // Set current user if user ID is available
        if (!userId.empty()) {
            SetCurrentUser(userId);
        }
        
        // Add conversation history to context if available
        for (const auto& historyItem : request.m_history) {
            AddSystemMessage("Previous interaction: " + historyItem);
        }
        
        // Add game info to context if available
        if (!request.m_gameInfo.empty()) {
            AddSystemMessage("Game context: " + request.m_gameInfo);
        }
        
        std::string result;
        
        // Process based on request type
        if (request.m_requestType == "script_generation") {
            // For script generation, use context-aware processing
            result = ProcessInputWithContext(
                request.m_query,
                "Request type: script generation; " + request.m_context,
                userId
            );
            
            // Extract script code from the response if possible
            size_t codeStart = result.find("```lua");
            size_t codeEnd = result.find("```", codeStart + 6);
            
            if (codeStart != std::string::npos && codeEnd != std::string::npos) {
                response.m_scriptCode = result.substr(codeStart + 6, codeEnd - (codeStart + 6));
                // Clean up the script code
                response.m_scriptCode = std::regex_replace(response.m_scriptCode, std::regex("^\\s+|\\s+$"), "");
            }
            
            // Generate suggestions for script generation
            response.m_suggestions.push_back("Optimize this script");
            response.m_suggestions.push_back("Explain how this script works");
            response.m_suggestions.push_back("Make this script more efficient");
            
        } else if (request.m_requestType == "debug") {
            // For debugging, use context-aware processing with debug context
            result = ProcessInputWithContext(
                request.m_query,
                "Request type: debug; " + request.m_context,
                userId
            );
            
            // Generate suggestions for debugging
            response.m_suggestions.push_back("Fix this error");
            response.m_suggestions.push_back("Optimize this code");
            response.m_suggestions.push_back("Explain this error");
            
        } else {
            // For general queries, use standard processing
            if (request.m_context.empty()) {
                result = ProcessInput(request.m_query, userId);
            } else {
                result = ProcessInputWithContext(request.m_query, request.m_context, userId);
            }
            
            // Generate general suggestions based on the query
            std::string lowerQuery = request.m_query;
            std::transform(lowerQuery.begin(), lowerQuery.end(), lowerQuery.begin(), 
                          [](unsigned char c) { return std::tolower(c); });
            
            if (lowerQuery.find("script") != std::string::npos) {
                response.m_suggestions.push_back("Generate a script for this");
                response.m_suggestions.push_back("Show me example scripts");
            } else if (lowerQuery.find("help") != std::string::npos) {
                response.m_suggestions.push_back("Show me how to use the executor");
                response.m_suggestions.push_back("What features are available?");
            } else {
                response.m_suggestions.push_back("Tell me more about this");
                response.m_suggestions.push_back("How can I use this?");
            }
        }
        
        // Set response content
        response.m_content = result;
        response.m_success = true;
        
    } catch (const std::exception& e) {
        // Handle exceptions
        response.m_success = false;
        response.m_errorMessage = "Error in GeneralAssistantModel::ProcessQuery: " + std::string(e.what());
        std::cerr << response.m_errorMessage << std::endl;
    }
    
    // Calculate processing time
    auto endTime = std::chrono::high_resolution_clock::now();
    response.m_processingTime = std::chrono::duration_cast<std::chrono::milliseconds>(
        endTime - startTime).count();
    
    return response;
}

// Implementation of asynchronous ProcessQuery method
void GeneralAssistantModel::ProcessQuery(const AIRequest& request, 
                                        std::function<void(const AIResponse&)> callback) {
    if (!callback) {
        return;
    }
    
    // Process in a background thread to avoid blocking
    std::thread([this, request, callback]() {
        AIResponse response = ProcessQuery(request);
        callback(response);
    }).detach();
}

} // namespace LocalModels
} // namespace AIFeatures
} // namespace iOS
