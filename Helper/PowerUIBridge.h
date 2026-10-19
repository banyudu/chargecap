#pragma once

#include <stddef.h>

// Thin bridge to PowerUI.framework's PowerUISmartChargeClient, the client that
// drives the charge limit built into macOS (System Settings -> Battery ->
// Charge Limit). The framework is private, so it is loaded at runtime and its
// Objective-C class is used dynamically.
//
// Every call returns 0 on success and -1 on failure. On failure, *error is set
// to a heap-allocated message which the caller must release with
// chargecap_powerui_free_error().

int chargecap_powerui_is_supported(void);
int chargecap_powerui_copy_limits(int *limits, int capacity, int *count, char **error);
int chargecap_powerui_read_limit(int *limit, int *enabled, char **error);
int chargecap_powerui_set_limit(int limit, char **error);
int chargecap_powerui_disable(char **error);
void chargecap_powerui_free_error(char *error);
