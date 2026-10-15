"""Generate a synthetic CT series (a sphere phantom) so the stack can be tested without real patient data.

usage: python3 make_sample_dicom.py OUT_DIR [--slices 40]
"""
import argparse
import datetime
from pathlib import Path

import numpy as np
from pydicom.dataset import FileDataset, FileMetaDataset
from pydicom.uid import CTImageStorage, ExplicitVRLittleEndian, generate_uid


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out_dir", type=Path)
    ap.add_argument("--slices", type=int, default=40)
    ap.add_argument("--size", type=int, default=256)
    args = ap.parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=True)

    study_uid, series_uid, frame_uid = generate_uid(), generate_uid(), generate_uid()
    today = datetime.date.today().strftime("%Y%m%d")
    n, spacing, thickness = args.size, 1.0, 2.5
    yy, xx = np.mgrid[0:n, 0:n] - n / 2
    radius = n * 0.35

    for i in range(args.slices):
        z = (i - args.slices / 2) * thickness
        r_slice = np.sqrt(max(radius**2 - (z * 2) ** 2, 0))
        img = np.full((n, n), -1000, dtype=np.int16)  # air
        img[xx**2 + yy**2 <= r_slice**2] = 40  # soft tissue
        img[(xx - n * 0.1) ** 2 + yy**2 <= (r_slice * 0.3) ** 2] = 700  # "bone"

        meta = FileMetaDataset()
        meta.MediaStorageSOPClassUID = CTImageStorage
        meta.MediaStorageSOPInstanceUID = generate_uid()
        meta.TransferSyntaxUID = ExplicitVRLittleEndian

        ds = FileDataset(None, {}, file_meta=meta, preamble=b"\0" * 128)
        ds.SOPClassUID, ds.SOPInstanceUID = CTImageStorage, meta.MediaStorageSOPInstanceUID
        ds.StudyInstanceUID, ds.SeriesInstanceUID, ds.FrameOfReferenceUID = study_uid, series_uid, frame_uid
        ds.PatientName, ds.PatientID, ds.PatientSex, ds.PatientBirthDate = "PHANTOM^SPHERE", "PHANTOM001", "O", ""
        ds.StudyDate = ds.SeriesDate = today
        ds.StudyTime = ds.SeriesTime = "120000"
        ds.StudyDescription, ds.SeriesDescription = "Synthetic phantom", "Sphere CT"
        ds.AccessionNumber, ds.StudyID = "ACC0001", "1"
        ds.Modality, ds.SeriesNumber, ds.InstanceNumber = "CT", 1, i + 1
        ds.ImagePositionPatient = [-n * spacing / 2, -n * spacing / 2, z]
        ds.ImageOrientationPatient = [1, 0, 0, 0, 1, 0]
        ds.SliceThickness, ds.SliceLocation = thickness, z
        ds.PixelSpacing = [spacing, spacing]
        ds.Rows = ds.Columns = n
        ds.SamplesPerPixel, ds.PhotometricInterpretation = 1, "MONOCHROME2"
        ds.BitsAllocated, ds.BitsStored, ds.HighBit, ds.PixelRepresentation = 16, 16, 15, 1
        ds.RescaleIntercept, ds.RescaleSlope = 0, 1
        ds.WindowCenter, ds.WindowWidth = 40, 400
        ds.PixelData = img.tobytes()
        ds.save_as(args.out_dir / f"CT{i + 1:04d}.dcm", enforce_file_format=True)

    print(f"wrote {args.slices} slices to {args.out_dir} (StudyInstanceUID={study_uid})")


if __name__ == "__main__":
    main()
