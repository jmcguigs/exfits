#include <erl_nif.h>
#include <fitsio.h>


static ERL_NIF_TERM hello(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
  return enif_make_atom(env, "nif_loaded");
}

static ERL_NIF_TERM open_fits(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    char filename[1024];
    ErlNifBinary bin;
    if (!enif_inspect_binary(env, argv[0], &bin) || bin.size >= sizeof(filename)) {
        return enif_make_badarg(env);
    }
    memcpy(filename, bin.data, bin.size);
    filename[bin.size] = '\0'; // Null-terminate for C string usage
    fitsfile *fptr;
    int status = 0;
    if (fits_open_file(&fptr, filename, READONLY, &status)) {
        return enif_make_tuple2(env, enif_make_atom(env, "error"), enif_make_int(env, status));
    }
    fits_close_file(fptr, &status);
    return enif_make_atom(env, "ok");
}

static ERL_NIF_TERM read_image(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    char filename[1024];
    ErlNifBinary bin_filename;
    if (!enif_inspect_binary(env, argv[0], &bin_filename) || bin_filename.size >= sizeof(filename)) {
        return enif_make_badarg(env);
    }
    memcpy(filename, bin_filename.data, bin_filename.size);
    filename[bin_filename.size] = '\0';
    fitsfile *fptr;
    int status = 0;
    if (fits_open_file(&fptr, filename, READONLY, &status)) {
        return enif_make_tuple2(env, enif_make_atom(env, "error"), enif_make_int(env, status));
    }
    int bitpix, naxis;
    long naxes[2] = {1,1};
    fits_get_img_param(fptr, 2, &bitpix, &naxis, naxes, &status);
    if (status || naxis != 2) {
        fits_close_file(fptr, &status);
        return enif_make_tuple2(env, enif_make_atom(env, "error"), enif_make_int(env, status));
    }
    long npixels = naxes[0] * naxes[1];
    float *pixels = (float *)malloc(npixels * sizeof(float));
    long fpixel[2] = {1,1};
    
    // Read all pixels as FLOAT values regardless of the actual BITPIX in the file
    fits_read_pix(fptr, TFLOAT, fpixel, npixels, NULL, pixels, NULL, &status);
    
    // Create an Erlang tuple with dimensions and binary data
    ERL_NIF_TERM width_term = enif_make_long(env, naxes[0]);
    ERL_NIF_TERM height_term = enif_make_long(env, naxes[1]);
    
    fits_close_file(fptr, &status);
    if (status) {
        free(pixels);
        return enif_make_tuple2(env, enif_make_atom(env, "error"), enif_make_int(env, status));
    }
    
    ERL_NIF_TERM result;
    ErlNifBinary bin_pixels;
    if (!enif_alloc_binary(npixels * sizeof(float), &bin_pixels)) {
        free(pixels);
        return enif_make_atom(env, "error");
    }
    
    // Copy the pixel data to the binary
    memcpy(bin_pixels.data, pixels, npixels * sizeof(float));
    free(pixels);
    
    result = enif_make_binary(env, &bin_pixels);
    
    // Return tuple with {ok, {width, height, data}}
    ERL_NIF_TERM dims_tuple = enif_make_tuple3(env, width_term, height_term, result);
    return enif_make_tuple2(env, enif_make_atom(env, "ok"), dims_tuple);
}

static ERL_NIF_TERM write_image(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    char filename[1024];
    ErlNifBinary bin_filename, bin_data;
    long width, height;
    int bitpix = FLOAT_IMG; // Default to float
    
    // Check for correct number of arguments (filename, data, width, height) or (filename, data, width, height, bitpix)
    if (argc < 4 || argc > 5) {
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
    
    // Get width and height
    if (!enif_get_long(env, argv[2], &width) || !enif_get_long(env, argv[3], &height)) {
        return enif_make_badarg(env);
    }
    
    // Get bitpix if provided (5th argument)
    if (argc == 5) {
        int temp_bitpix;
        if (!enif_get_int(env, argv[4], &temp_bitpix)) {
            return enif_make_badarg(env);
        }
        bitpix = temp_bitpix;
    }
    
    // Validate dimensions for float data (4 bytes per value)
    if (width * height * sizeof(float) != bin_data.size) {
        return enif_make_tuple2(env, enif_make_atom(env, "error"), 
                               enif_make_atom(env, "dimensions_mismatch"));
    }
    
    fitsfile *fptr;
    int status = 0;
    long naxes[2] = {width, height};
    if (fits_create_file(&fptr, filename, &status)) {
        return enif_make_tuple2(env, enif_make_atom(env, "error"), enif_make_int(env, status));
    }
    
    // Create image with the specified bitpix (or default FLOAT_IMG)
    if (fits_create_img(fptr, bitpix, 2, naxes, &status)) {
        fits_close_file(fptr, &status);
        return enif_make_tuple2(env, enif_make_atom(env, "error"), enif_make_int(env, status));
    }
    
    long fpixel[2] = {1,1};
    // Calculate total number of pixels
    long npixels = width * height;
    
    // We always write as TFLOAT since that's our internal format
    if (fits_write_pix(fptr, TFLOAT, fpixel, npixels, bin_data.data, &status)) {
        fits_close_file(fptr, &status);
        return enif_make_tuple2(env, enif_make_atom(env, "error"), enif_make_int(env, status));
    }
    
    fits_close_file(fptr, &status);
    if (status) {
        return enif_make_tuple2(env, enif_make_atom(env, "error"), enif_make_int(env, status));
    }
    return enif_make_atom(env, "ok");
}


static ERL_NIF_TERM read_header(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    char filename[1024];
    ErlNifBinary bin_filename;
    
    // Get filename
    if (!enif_inspect_binary(env, argv[0], &bin_filename) || bin_filename.size >= sizeof(filename)) {
        return enif_make_badarg(env);
    }
    memcpy(filename, bin_filename.data, bin_filename.size);
    filename[bin_filename.size] = '\0';
    
    fitsfile *fptr;
    int status = 0;
    
    // Open the FITS file
    if (fits_open_file(&fptr, filename, READONLY, &status)) {
        return enif_make_tuple2(env, enif_make_atom(env, "error"), 
                               enif_make_int(env, status));
    }
    
    // Get number of keys in header
    int nkeys, keypos, hdutype;
    if (fits_get_hdrpos(fptr, &nkeys, &keypos, &status)) {
        fits_close_file(fptr, &status);
        return enif_make_tuple2(env, enif_make_atom(env, "error"), 
                               enif_make_int(env, status));
    }
    
    // Create an empty map to store header data
    ERL_NIF_TERM header_map = enif_make_new_map(env);
    
    // Read each keyword
    for (int i = 1; i <= nkeys; i++) {
        char card[FLEN_CARD];
        char key[FLEN_KEYWORD], value[FLEN_VALUE];
        char comment[FLEN_COMMENT];
        int keylen;
        
        // Read the next header card
        if (fits_read_record(fptr, i, card, &status)) {
            fits_close_file(fptr, &status);
            return enif_make_tuple2(env, enif_make_atom(env, "error"), 
                                   enif_make_int(env, status));
        }
        
        // Parse the card to get keyword name and value
        if (fits_get_keyname(card, key, &keylen, &status) == 0) {
            // Skip COMMENT, HISTORY, and blank keywords
            if (strcmp(key, "COMMENT") != 0 && strcmp(key, "HISTORY") != 0 && strlen(key) > 0) {
                int value_type;
                fits_parse_value(card, value, comment, &status);
                
                // Convert keyword to atom and value to appropriate Erlang term
                ERL_NIF_TERM key_term = enif_make_atom(env, key);
                ERL_NIF_TERM value_term;
                
                // Determine the type of value and convert accordingly
                if (strncmp(value, "'", 1) == 0) {
                    // String value (remove quotes)
                    size_t len = strlen(value);
                    if (len >= 2 && value[0] == '\'' && value[len-1] == '\'') {
                        value[len-1] = '\0';  // Remove trailing quote
                        value_term = enif_make_string(env, value+1, ERL_NIF_LATIN1);
                    } else {
                        value_term = enif_make_string(env, value, ERL_NIF_LATIN1);
                    }
                } else if (strchr(value, '.') != NULL) {
                    // Float value
                    double dval;
                    sscanf(value, "%lf", &dval);
                    value_term = enif_make_double(env, dval);
                } else {
                    // Try as integer, fall back to string
                    char *endptr;
                    long ival = strtol(value, &endptr, 10);
                    if (*endptr == '\0') {
                        value_term = enif_make_long(env, ival);
                    } else {
                        value_term = enif_make_string(env, value, ERL_NIF_LATIN1);
                    }
                }
                
                // Add to map
                enif_make_map_put(env, header_map, key_term, value_term, &header_map);
            }
        }
    }
    
    fits_close_file(fptr, &status);
    if (status) {
        return enif_make_tuple2(env, enif_make_atom(env, "error"), 
                               enif_make_int(env, status));
    }
    
    return enif_make_tuple2(env, enif_make_atom(env, "ok"), header_map);
}

// Write header cards to a FITS file
static ERL_NIF_TERM write_header_cards(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    char filename[1024];
    ErlNifBinary bin_filename;
    
    // Get filename
    if (!enif_inspect_binary(env, argv[0], &bin_filename) || bin_filename.size >= sizeof(filename)) {
        return enif_make_badarg(env);
    }
    memcpy(filename, bin_filename.data, bin_filename.size);
    filename[bin_filename.size] = '\0';
    
    // Get header map
    if (!enif_is_map(env, argv[1])) {
        return enif_make_badarg(env);
    }
    ERL_NIF_TERM header_map = argv[1];
    
    // Open the FITS file for updating
    fitsfile *fptr;
    int status = 0;
    
    // Check if file exists
    FILE *f = fopen(filename, "r");
    if (f == NULL) {
        return enif_make_tuple2(env, enif_make_atom(env, "error"), 
                               enif_make_atom(env, "file_not_found"));
    }
    fclose(f);
    
    if (fits_open_file(&fptr, filename, READWRITE, &status)) {
        return enif_make_tuple2(env, enif_make_atom(env, "error"), 
                               enif_make_int(env, status));
    }
    
    // Move to the primary HDU
    if (fits_movabs_hdu(fptr, 1, NULL, &status)) {
        fits_close_file(fptr, &status);
        return enif_make_tuple2(env, enif_make_atom(env, "error"), 
                               enif_make_int(env, status));
    }
    
    // Get map size
    size_t map_size;
    if (!enif_get_map_size(env, header_map, &map_size)) {
        fits_close_file(fptr, &status);
        return enif_make_badarg(env);
    }
    
    // Get iterator
    ErlNifMapIterator iter;
    if (!enif_map_iterator_create(env, header_map, &iter, ERL_NIF_MAP_ITERATOR_FIRST)) {
        fits_close_file(fptr, &status);
        return enif_make_badarg(env);
    }
    
    // Skip certain keywords that we shouldn't modify
    const char* skip_keys[] = {"SIMPLE", "BITPIX", "NAXIS", "NAXIS1", "NAXIS2", "NAXIS3", "END", NULL};
    
    // Iterate through the map
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
        if (skip) continue;
        
        // Handle different value types
        int key_status = 0; // Separate status for each key update
        if (enif_is_number(env, value)) {
            double dval;
            long ival;
            
            if (enif_get_long(env, value, &ival)) {
                // Integer value
                fits_update_key(fptr, TLONG, key_str, &ival, NULL, &key_status);
                if (key_status) {
                    // Log the error for debugging
                    char error_text[FLEN_STATUS];
                    fits_get_errstatus(key_status, error_text);
                    fprintf(stderr, "FITS error updating key '%s' with value %ld: %d (%s)\n", 
                            key_str, ival, key_status, error_text);
                }
            } else if (enif_get_double(env, value, &dval)) {
                // Double value
                fits_update_key(fptr, TDOUBLE, key_str, &dval, NULL, &key_status);
                if (key_status) {
                    // Log the error for debugging
                    char error_text[FLEN_STATUS];
                    fits_get_errstatus(key_status, error_text);
                    fprintf(stderr, "FITS error updating key '%s' with value %f: %d (%s)\n", 
                            key_str, dval, key_status, error_text);
                }
            }
        } else if (enif_is_binary(env, value) || enif_is_list(env, value)) {
            // String value - could be binary or char list
            char value_str[FLEN_VALUE];
            if (enif_get_string(env, value, value_str, sizeof(value_str), ERL_NIF_LATIN1) > 0) {
                fits_update_key(fptr, TSTRING, key_str, value_str, NULL, &key_status);
                if (key_status) {
                    // Log the error for debugging
                    char error_text[FLEN_STATUS];
                    fits_get_errstatus(key_status, error_text);
                    fprintf(stderr, "FITS error updating key '%s' with string value: %d (%s)\n", 
                            key_str, key_status, error_text);
                }
            }
        }
        
        // Use main status only for critical errors
        if (key_status > 0) {
            // Non-critical errors in individual key updates don't abort the whole process
            fprintf(stderr, "Warning: Failed to update key '%s', continuing with others\n", key_str);
        } 
        
        // Only abort for serious issues
        if (status > 0) {
            break;
        }
    } while (enif_map_iterator_next(env, &iter));
    
    enif_map_iterator_destroy(env, &iter);
    fits_close_file(fptr, &status);
    
    if (status) {
        return enif_make_tuple2(env, enif_make_atom(env, "error"), 
                               enif_make_int(env, status));
    }
    
    return enif_make_atom(env, "ok");
}

// Include the write_fits_file function
#include "write_fits.c"

static ErlNifFunc nif_funcs[] = {
    {"hello", 0, hello},
    {"open_fits", 1, open_fits},
    {"read_image", 1, read_image},
    {"read_header", 1, read_header},
    {"write_image", 4, write_image},
    {"write_image", 5, write_image},
    {"write_header_cards", 2, write_header_cards},
    {"write_fits_file", 4, write_fits_file},
    {"write_fits_file", 5, write_fits_file},
    {"write_fits_file", 6, write_fits_file}
};

ERL_NIF_INIT(Elixir.ExFITS.NIF, nif_funcs, NULL, NULL, NULL, NULL);