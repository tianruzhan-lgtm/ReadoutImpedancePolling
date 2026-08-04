# Helper Functions. Written by Seo Kyung Brian Ahn for the Chiara Daraio Lab, 11/20/2025
import os

def initializeData(subDirectoryData, fileIDData, headerList):
    """
    Ensures a .txt file exists in subDirectoryData with name fileIDData.
    If the file exists, prompts user whether to overwrite.
    If user says no, asks for a new filename.

    Returns the final full filepath that was created.
    """

    # --- Step 1: Ensure directory exists ---
    os.makedirs(subDirectoryData, exist_ok=True)

    # Construct full path with .txt extension
    file_path = os.path.join(subDirectoryData, fileIDData + ".txt")

    # --- Step 2: Check if file exists ---
    if not os.path.exists(file_path):
        # File does NOT exist, so create it
        with open(file_path, 'w') as f:
            f.write("\t".join(headerList) + "\n")
        print(f"Created new file: {file_path}")
        return file_path

    # --- Step 3: File exists → ask overwrite ---
    print(f"File already exists: {file_path}")
    user_input = input("Overwrite? (y/n): ").strip().lower()

    if user_input == 'y':
        # User wants to overwrite
        with open(file_path, 'w') as f:
            f.write("\t".join(headerList) + "\n")
        print(f"File overwritten: {file_path}")
        return file_path

    # --- Step 4: User does NOT want to overwrite ---
    new_name = input("Enter new file name (without extension): ").strip()

    # Build new path
    new_file_path = os.path.join(subDirectoryData, new_name + ".txt")

    # Create the new file
    with open(new_file_path, 'w') as f:
        f.write("\t".join(headerList) + "\n")
    print(f"Created new file: {new_file_path}")

    # TODO: Insert headers into file to let MATLAB know of experiment parameters

    return new_file_path

def recordData(outputFile, IAAvgData, headerList):
    """ Takes dataList and appends it to the file being referenced by outputFile.
    """
    precision = {
        "time":10,
        "temperature": 4,
        "humidity": 4
    }

    rowBuffer = []
    for key in headerList:
        values = IAAvgData[key]
        if not values:
            last_val = "" # Handles exception in cases where there is no populated data.
        else:
            last_val = values[-1]

        if isinstance(last_val, (int, float)):
            # Determine precision: use key-specific or default=6
            sigfigs = precision.get(key, 6)
            last_val_str = f"{last_val:.{sigfigs}g}"
        else:
            # Non-numeric values (strings, etc.)
            last_val_str = str(last_val)

        rowBuffer.append(str(last_val_str))
    line = "\t".join(rowBuffer) + "\n"

    # Append to file (do NOT overwrite)
    with open(outputFile, "a") as f:
        f.write(line)