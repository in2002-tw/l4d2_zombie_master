/**
 * l4d2_log_lib.
 *
 * Usage:
 *   #include <l4d2_log_lib>
 *
 *   Log_SetLevel("GridLib", LOG_INFO);
 *
 *   Log_Info("GridLib",  "Precompute complete: %d cells", count);
 *   Log_Warn("GridLib",  "Budget exceeded: %.1fms", ms);
 *   Log_Debug("GridLib", "Query details: visited=%d", visited);
 */

#if defined _l4d2_log_lib_included
 #endinput
#endif
#define _l4d2_log_lib_included

#define LOG_OFF   0
#define LOG_ERROR 1
#define LOG_WARN  2
#define LOG_INFO  3
#define LOG_DEBUG 4
#define LOG_TRACE 5

// Default level applied to any channel that hasn't had SetLevel called on it.
#define LOG_DEFAULT_LEVEL LOG_INFO

static StringMap g_LogLevels = null;

static stock void Log_EnsureInit()
{
	if (g_LogLevels == null)
		g_LogLevels = new StringMap();
}

static stock int Log_GetChannelLevel(const char[] channel)
{
	Log_EnsureInit();
	int level;
	if (!g_LogLevels.GetValue(channel, level))
		return LOG_DEFAULT_LEVEL;
	return level;
}

/**
 * Set the log level for a named channel.
 * Use one of the LOG_* constants. Clamped to [LOG_OFF, LOG_TRACE].
 */
stock void Log_SetLevel(const char[] channel, int level)
{
	Log_EnsureInit();
	if (level < LOG_OFF)   level = LOG_OFF;
	if (level > LOG_TRACE) level = LOG_TRACE;
	g_LogLevels.SetValue(channel, level);
}

/**
 * Retrieve a channel's current log level (returns LOG_DEFAULT_LEVEL
 * for channels never set).
 */
stock int Log_GetLevel(const char[] channel)
{
	return Log_GetChannelLevel(channel);
}

static stock void Log_Emit(int level, const char[] levelTag, const char[] channel, const char[] buffer)
{
	if (level <= LOG_WARN)
		LogError("[%s][%s] %s", channel, levelTag, buffer);
	else
		LogMessage("[%s][%s] %s", channel, levelTag, buffer);
}

stock void Log_Error(const char[] channel, const char[] fmt, any ...)
{
	if (Log_GetChannelLevel(channel) < LOG_ERROR) return;
	char buffer[512];
	VFormat(buffer, sizeof(buffer), fmt, 3);
	Log_Emit(LOG_ERROR, "ERROR", channel, buffer);
}

stock void Log_Warn(const char[] channel, const char[] fmt, any ...)
{
	if (Log_GetChannelLevel(channel) < LOG_WARN) return;
	char buffer[512];
	VFormat(buffer, sizeof(buffer), fmt, 3);
	Log_Emit(LOG_WARN, "WARN", channel, buffer);
}

stock void Log_Info(const char[] channel, const char[] fmt, any ...)
{
	if (Log_GetChannelLevel(channel) < LOG_INFO) return;
	char buffer[512];
	VFormat(buffer, sizeof(buffer), fmt, 3);
	Log_Emit(LOG_INFO, "INFO", channel, buffer);
}

stock void Log_Debug(const char[] channel, const char[] fmt, any ...)
{
	if (Log_GetChannelLevel(channel) < LOG_DEBUG) return;
	char buffer[512];
	VFormat(buffer, sizeof(buffer), fmt, 3);
	Log_Emit(LOG_DEBUG, "DEBUG", channel, buffer);
}

stock void Log_Trace(const char[] channel, const char[] fmt, any ...)
{
	if (Log_GetChannelLevel(channel) < LOG_TRACE) return;
	char buffer[512];
	VFormat(buffer, sizeof(buffer), fmt, 3);
	Log_Emit(LOG_TRACE, "TRACE", channel, buffer);
}
