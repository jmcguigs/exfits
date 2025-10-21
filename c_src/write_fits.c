#include <erl_nif.h>
#include <fitsio.h>
#include <stdio.h>
#include <string.h>

// Function to debug binary float data
static void debug_float_data(void* data, size_t nbytes, const char* label) {
    if (data == NULL) {
        fprintf(stderr, "ERROR: %s - data pointer is NULL\n", label);
        return;
    }
    
    fprintf(stderr, "=== Debugging %s ===\n", label);
    fprintf(stderr, "Memory address: %p, Size: %zu bytes\n", data, nbytes);
    
    // Print first few values as floats
    float* fdata = (float*)data;
    size_t nvalues = nbytes / sizeof(float);
    size_t max_display = nvalues < 10 ? nvalues : 10;
    
    fprintf(stderr, "First %zu float values:\n", max_display);
    for (size_t i = 0; i < max_display; i++) {
        fprintf(stderr, "[%zu]: %f\n", i, fdata[i]);
    }
    
    // Print as bytes for binary inspection
    unsigned char* bdata = (unsigned char*)data;
    fprintf(stderr, "First 40 bytes in hex:\n");
    for (size_t i = 0; i < 40 && i < nbytes; i++) {
        fprintf(stderr, "%02x ", bdata[i]);
        if ((i+1) % 4 == 0) fprintf(stderr, " "); // Group by 4 bytes (float32)
        if ((i+1) % 16 == 0) fprintf(stderr, "\n");
    }
    fprintf(stderr, "\n");
    
    // Check for all zeros
    size_t zero_count = 0;
    for (size_t i = 0; i < nbytes; i++) {
        if (bdata[i] == 0) zero_count++;
    }
    
    if (zero_count == nbytes) {
        fprintf(stderr, "WARNING: All bytes are zero!\n");
    } else {
        float zero_percent = ((float)zero_count / nbytes) * 100.0;
        fprintf(stderr, "Zero bytes: %zu/%zu (%.2f%%)\n", zero_count, nbytes, zero_percent);
    }
    
    fprintf(stderr, "=== End debug %s ===\n\n", label);
}

// Helper function to write header cards to a FITS file
static int write_header_to_fits(ErlNifEnv *env, fitsfile *fptr, ERL_NIF_TERM headers, int *status) {
    unsigned int num_cards;
    if (!enif_get_list_length(env, headers, &num_cards)) {
        return 0;
    }

    ERL_NIF_TERM head, tail = headers;
    for (unsigned int i = 0; i < num_cards; i++) {
        if (!enif_get_list_cell(env, tail, &head, &tail)) {
            break;
        }

        char card[81];
        if (enif_get_string(env, head, card, sizeof(card), ERL_NIF_LATIN1)) {
            fits_write_record(fptr, card, status);
            if (*status) {
                return 0;
            }
        } else {
            return 0;
        }
    }

    return 1;
}

/**
 * Writes a FITS file from Elixir data.
 * 
 * This function handles both single and multi-extension FITS files.
 * It supports various data types and can handle 2D and 3D arrays.
 * 
 * Args:
 *   - filename: Path to output FITS file
 *   - data: List of image data (for multi-extension) or a single image tensor
 *   - headers: List of header card lists (for multi-extension) or a single list of header cards
 *   - bitpix: FITS BITPIX value (-32 for float, 16 for INT16, etc.)
 *   - options: Optional map with additional settings
 *   - multi: Boolean flag indicating if this is a multi-extension file (true) or single (false)
 * 
 * Returns:
 *   {:ok, filename} on success
 *   {:error, reason} on failure
 */
// writes both image data and header
static ERL_NIF_TERM write_fits_file(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    char filename[1024];
    ErlNifBinary bin_filename, bin_data;
    long width, height;
    int bitpix = FLOAT_IMG; // Default to float
    
    // Check arguments (filename, data, width, height, [optional]bitpix, [optional]header)
    if (argc < 4 || argc > 6) {
        return enif_make_badarg(env);
    }
    
    // Get filename
    if (!enif_inspect_binary(env, argv[0], &bin_filename) || bin_filename.size >= sizeof(filename)) {
        return enif_make_badarg(env);
    }
    memcpy(filename, bin_filename.data, bin_filename.size);
    filename[bin_filename.size] = '\0';
    
    // Get pixel data
    if (!enif_inspect_binary(env, argv[1], &bin_data)) {
        return enif_make_badarg(env);
    }
    
    // Debug the binary data
    debug_float_data(bin_data.data, bin_data.size, "input data");
    
    // Get width and height
    if (!enif_get_long(env, argv[2], &width) || !enif_get_long(env, argv[3], &height)) {
        return enif_make_badarg(env);
    }
    
    // Get bitpix if provided (5th argument)
    if (argc >= 5) {
        int temp_bitpix;
        if (!enif_get_int(env, argv[4], &temp_bitpix)) {
            return enif_make_badarg(env);
        }
        bitpix = temp_bitpix;
    }
    
    // Get header map if provided (6th argument)
    ERL_NIF_TERM header_map = 0;
    int has_header = 0;
    
    if (argc == 6) {
        if (!enif_is_map(env, argv[5])) {
            return enif_make_badarg(env);
        }
        header_map = argv[5];
        has_header = 1;
    }
    
    // Validate dimensions for float data (4 bytes per value)
    if (width * height * sizeof(float) != bin_data.size) {
        fprintf(stderr, "ERROR: Dimensions mismatch - width=%ld, height=%ld, expected bytes=%ld, actual bytes=%zu\n",
                width, height, width * height * sizeof(float), bin_data.size);
        return enif_make_tuple2(env, enif_make_atom(env, "error"), 
                               enif_make_atom(env, "dimensions_mismatch"));
    }
    
    // Print debugging info
    fprintf(stderr, "Creating FITS file: %s\n", filename);
    fprintf(stderr, "Dimensions: %ldx%ld (%ld pixels)\n", width, height, width * height);
    fprintf(stderr, "BITPIX: %d\n", bitpix);
    
    // Create a copy of the data that we can work with safely
    float *pixels = (float *)malloc(bin_data.size);
    if (pixels == NULL) {
        fprintf(stderr, "Failed to allocate memory for pixel data\n");
        return enif_make_tuple2(env, enif_make_atom(env, "error"), 
                               enif_make_atom(env, "memory_allocation_failure"));
    }
    memcpy(pixels, bin_data.data, bin_data.size);
    
    // Debug the copied data to make sure it's good
    debug_float_data(pixels, bin_data.size, "copied data");
    
    // Create the new FITS file
    fitsfile *fptr;
    int status = 0;
    long naxes[2] = {width, height};
    
    // Remove any existing file with the same name
    remove(filename);
    
    // Create the file
    if (fits_create_file(&fptr, filename, &status)) {
        char error_text[FLEN_STATUS];
        fits_get_errstatus(status, error_text);
        fprintf(stderr, "Error creating FITS file: %s (status=%d)\n", error_text, status);
        free(pixels);
        return enif_make_tuple2(env, enif_make_atom(env, "error"), enif_make_int(env, status));
    }
    
    // Create image with the specified bitpix
    if (fits_create_img(fptr, bitpix, 2, naxes, &status)) {
        char error_text[FLEN_STATUS];
        fits_get_errstatus(status, error_text);
        fprintf(stderr, "Error creating image: %s (status=%d)\n", error_text, status);
        fits_close_file(fptr, &status);
        free(pixels);
        return enif_make_tuple2(env, enif_make_atom(env, "error"), enif_make_int(env, status));
    }
    
    // Write pixel data
    long fpixel[2] = {1, 1}; // FITS uses 1-based indexing
    long npixels = width * height;
    
    // Always write data as float (TFLOAT) since that's what we have from Elixir
    fprintf(stderr, "Writing %ld pixels as TFLOAT\n", npixels);
    
    if (fits_write_pix(fptr, TFLOAT, fpixel, npixels, pixels, &status)) {
        char error_text[FLEN_STATUS];
        fits_get_errstatus(status, error_text);
        fprintf(stderr, "Error writing pixels: %s (status=%d)\n", error_text, status);
        fits_close_file(fptr, &status);
        free(pixels);
        return enif_make_tuple2(env, enif_make_atom(env, "error"), enif_make_int(env, status));
    }
    
    // Free the pixel data since we're done with it
    free(pixels);
    
    // Write header cards if provided
    if (has_header) {
        // Skip certain keywords that we shouldn't modify
        const char* skip_keys[] = {"SIMPLE", "BITPIX", "NAXIS", "NAXIS1", "NAXIS2", "NAXIS3", "END", NULL};
        
        // Get iterator for the header map
        ErlNifMapIterator iter;
        if (!enif_map_iterator_create(env, header_map, &iter, ERL_NIF_MAP_ITERATOR_FIRST)) {
            fits_close_file(fptr, &status);
            return enif_make_badarg(env);
        }
        
        fprintf(stderr, "Writing header cards\n");
        
        // Iterate through all header cards
        do {
            ERL_NIF_TERM key, value;
            if (!enif_map_iterator_get_pair(env, &iter, &key, &value)) {
                continue;
            }
            
            // Get key as a string
            char key_str[FLEN_KEYWORD];
            if (!enif_get_atom(env, key, key_str, sizeof(key_str), ERL_NIF_LATIN1)) {
                continue;
            }
            
            // Skip structural keywords
            int skip = 0;
            for (int i = 0; skip_keys[i] != NULL; i++) {
                if (strcmp(key_str, skip_keys[i]) == 0) {
                    skip = 1;
                    break;
                }
            }
            if (skip) {
                fprintf(stderr, "Skipping header key: %s\n", key_str);
                continue;
            }
            
            // Update header based on value type
            int key_status = 0; // Separate status for each key update
            if (enif_is_number(env, value)) {
                double dval;
                long ival;
                
                if (enif_get_long(env, value, &ival)) {
                    // Integer value
                    fprintf(stderr, "Updating header key %s = %ld (integer)\n", key_str, ival);
                    fits_update_key(fptr, TLONG, key_str, &ival, NULL, &key_status);
                } else if (enif_get_double(env, value, &dval)) {
                    // Double value
                    fprintf(stderr, "Updating header key %s = %f (double)\n", key_str, dval);
                    fits_update_key(fptr, TDOUBLE, key_str, &dval, NULL, &key_status);
                }
            } else if (enif_is_binary(env, value) || enif_is_list(env, value)) {
                // String value - could be binary or char list
                char value_str[FLEN_VALUE];
                if (enif_get_string(env, value, value_str, sizeof(value_str), ERL_NIF_LATIN1) > 0) {
                    fprintf(stderr, "Updating header key %s = '%s' (string)\n", key_str, value_str);
                    fits_update_key(fptr, TSTRING, key_str, value_str, NULL, &key_status);
                }
            }
            
            // Non-critical errors in individual header updates don't stop the process
            if (key_status) {
                char error_text[FLEN_STATUS];
                fits_get_errstatus(key_status, error_text);
                fprintf(stderr, "Warning: Failed to update header key '%s': %s (%d)\n", 
                        key_str, error_text, key_status);
            }
        } while (enif_map_iterator_next(env, &iter));
        
        enif_map_iterator_destroy(env, &iter);
    }
    
    // Close file and return result
    fits_close_file(fptr, &status);
    if (status) {
        char error_text[FLEN_STATUS];
        fits_get_errstatus(status, error_text);
        fprintf(stderr, "Error closing file: %s (status=%d)\n", error_text, status);
        return enif_make_tuple2(env, enif_make_atom(env, "error"), enif_make_int(env, status));
    }
    
    fprintf(stderr, "Successfully wrote FITS file: %s\n", filename);
    return enif_make_atom(env, "ok");
}
