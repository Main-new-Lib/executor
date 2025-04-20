#include "../../objc_isolation.h"


#pragma once

#include <string>
#include <vector>
#include <functional>
#include <memory>
#include <unordered_map>

namespace iOS {
namespace AIFeatures {

/**
 * @class OnlineService
 * @brief Service for interacting with online AI capabilities
 * 
 * This class provides methods for securely connecting to online AI services
 * when internet connectivity is available, with proper fallback to local
 * models when offline or when privacy is preferred.
 */
class OnlineService {
public:
    // Request structure
    struct Request {
        std::string m_endpoint;       // API endpoint
        std::string m_method;         // HTTP method (GET, POST, etc.)
        std::string m_body;           // Request body
        std::vector<std::pair<std::string, std::string>> m_headers; // Request headers
        uint32_t m_timeoutMs;         // Timeout in milliseconds
        bool m_useCache;              // Whether to use cached response if available
        
        Request() : m_method("GET"), m_timeoutMs(10000), m_useCache(false) {}
    };
    
    // Response structure
    struct Response {
        bool m_success;               // Success flag
        int m_statusCode;             // HTTP status code
        std::string m_body;           // Response body
        std::unordered_map<std::string, std::string> m_headers; // Response headers
        std::string m_errorMessage;   // Error message if failed
        uint64_t m_responseTimeMs;    // Response time in milliseconds
        bool m_fromCache;             // Whether response is from cache
        
        Response() : m_success(false), m_statusCode(0), m_responseTimeMs(0), m_fromCache(false) {}
    };
    
    // Network status
    enum class NetworkStatus {
        Unknown,
        NotReachable,
        ReachableViaWiFi,
        ReachableViaCellular
    };
    
    // Callback types
    using ResponseCallback = std::function<void(const Response&)>;
    using NetworkStatusCallback = std::function<void(NetworkStatus)>;
    
private:
    std::string m_apiKey;             // API key
    std::string m_baseUrl;            // Base URL for API requests
    std::string m_userAgent;          // User agent for API requests
    std::unordered_map<std::string, std::string> m_defaultHeaders; // Default headers
    std::unordered_map<std::string, Response> m_responseCache; // Response cache
    NetworkStatus m_currentNetworkStatus; // Current network status
    bool m_isInitialized;             // Initialization flag
    uint64_t m_requestCount;          // Request counter
    uint32_t m_defaultTimeoutMs;      // Default timeout in milliseconds
    NetworkStatusCallback m_networkStatusCallback; // Network status callback
    void* m_reachability;             // Opaque pointer to reachability object
    bool m_enableEncryption;          // Whether to encrypt communication
    std::string m_encryptionKey;      // Encryption key
    bool m_bypassCertificateValidation; // Whether to bypass certificate validation
    
    // Private methods
    void MonitorNetworkStatus();
    void UpdateNetworkStatus(NetworkStatus status);
    std::string EncryptData(const std::string& data);
    std::string DecryptData(const std::string& data);
    bool ValidateResponse(const Response& response);
    std::string HashRequest(const Request& request);
    void CacheResponse(const Request& request, const Response& response);
    Response GetCachedResponse(const Request& request);
    void CleanCache();
    void* CreateNSURLRequest(const Request& request);
    Response ParseNSURLResponse(void* urlResponse, void* data, void* error);
    std::string EscapeJSON(const std::string& input);
    std::string UnescapeJSON(const std::string& input);
    std::string URLEncode(const std::string& input);
    
public:
    /**
     * @brief Constructor
     */
    OnlineService();
    
    /**
     * @brief Destructor
     */
    ~OnlineService();
    
    /**
     * @brief Initialize the service
     * @param baseUrl Base URL for API requests
     * @param apiKey API key
     * @return True if initialization succeeded, false otherwise
     */
    bool Initialize(const std::string& baseUrl, const std::string& apiKey = "");
    
    /**
     * @brief Check if the service is initialized
     * @return True if initialized, false otherwise
     */
    bool IsInitialized() const;
    
    /**
     * @brief Send a request
     * @param request Request to send
     * @param callback Function to call with the response
     */
    void SendRequest(const Request& request, ResponseCallback callback);
    
    /**
     * @brief Send a request synchronously
     * @param request Request to send
     * @return Response
     */
    Response SendRequestSync(const Request& request);
    
    /**
     * @brief Set API key
     * @param apiKey API key
     */
    void SetAPIKey(const std::string& apiKey);
    
    /**
     * @brief Set base URL
     * @param baseUrl Base URL
     */
    void SetBaseUrl(const std::string& baseUrl);
    
    /**
     * @brief Set user agent
     * @param userAgent User agent
     */
    void SetUserAgent(const std::string& userAgent);
    
    /**
     * @brief Set default timeout
     * @param timeoutMs Default timeout in milliseconds
     */
    void SetDefaultTimeout(uint32_t timeoutMs);
    
    /**
     * @brief Set default header
     * @param key Header key
     * @param value Header value
     */
    void SetDefaultHeader(const std::string& key, const std::string& value);
    
    /**
     * @brief Remove default header
     * @param key Header key
     */
    void RemoveDefaultHeader(const std::string& key);
    
    /**
     * @brief Clear all default headers
     */
    void ClearDefaultHeaders();
    
    /**
     * @brief Set network status callback
     * @param callback Function to call when network status changes
     */
    void SetNetworkStatusCallback(NetworkStatusCallback callback);
    
    /**
     * @brief Get current network status
     * @return Current network status
     */
    NetworkStatus GetNetworkStatus() const;
    
    /**
     * @brief Check if network is reachable
     * @return True if network is reachable, false otherwise
     */
    bool IsNetworkReachable() const;
    
    /**
     * @brief Enable or disable encryption
     * @param enable Whether to enable encryption
     * @param key Encryption key (optional, generated if not provided)
     */
    void SetEncryption(bool enable, const std::string& key = "");
    
    /**
     * @brief Enable or disable certificate validation bypass
     * @param bypass Whether to bypass certificate validation
     */
    void SetBypassCertificateValidation(bool bypass);
    
    /**
     * @brief Clear response cache
     */
    void ClearCache();
    
    /**
     * @brief Create a POST request for AI processing
     * @param endpoint API endpoint
     * @param query User query
     * @param context Additional context
     * @param requestType Request type (e.g., "script_generation", "debug")
     * @return Request object ready to send
     */
    Request CreateAIRequest(const std::string& endpoint, 
                          const std::string& query,
                          const std::string& context = "",
                          const std::string& requestType = "general");
    
    /**
     * @brief Parse AI response
     * @param response Response from API
     */
    std::string ParseAIResponse(const Response& response);
    
    /**
     * @brief Create a standard API GET request
     * @param endpoint API endpoint
     * @param queryParams Query parameters
     * @return Request object ready to send
     */
    Request CreateGETRequest(const std::string& endpoint,
                           const std::unordered_map<std::string, std::string>& queryParams = {});
    
    /**
     * @brief Create a standard API POST request
     * @param endpoint API endpoint
     * @param body Request body
     * @param contentType Content type
     * @return Request object ready to send
     */
    Request CreatePOSTRequest(const std::string& endpoint,
                            const std::string& body,
                            const std::string& contentType = "application/json");
};

} // namespace AIFeatures
} // namespace iOS
