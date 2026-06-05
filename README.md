# Pitch Range and Speech Rate in Valencia Spanish (PRESEEA-Valencia)

Derived data and processing notebooks for the study:

> Cabedo Nebot, A. (*under review*). A Sociolinguistic Approach to Pitch Range and Speech Rate in an Oral Spanish Corpus from Valencia. *Estudios de Fonética Experimental*.

This repository contains the acoustic measurement tables and the processing pipeline used to extract them from the PRESEEA-Valencia corpus. Raw audio files and verbatim transcriptions are **not shared** here (see below).

---

## Repository structure

```
.
├── notebooks/
│   ├── 01_whisper_transcription.ipynb   # Automatic transcription with Whisper
│   └── 02_forced_alignment.ipynb        # Forced alignment with Montreal Forced Aligner
├── ip_measures.csv                      # Intonational-phrase-level measures
├── turn_measures.csv                    # Speech-turn-level measures
├── speaker_measures.csv                 # Speaker-level summary measures
└── README.md
```

---

## Notebooks

Both notebooks were adapted from a local processing script with the assistance of Google Gemini and are designed to run on Google Colab (free GPU/CPU tier). Local CPU-only processing with Whisper on a standard laptop is feasible but substantially slower; Colab is recommended for the transcription stage in particular.

### `01_whisper_transcription.ipynb`

Transcribes each recording using [OpenAI Whisper](https://github.com/openai/whisper) (model: `large-v3-turbo`). For each transcribed segment, Whisper returns a confidence score (0–1) that is stored in the output and later used as a quality filter. The notebook:

- loads the audio files from Google Drive,
- segments long recordings into short speaker-turn units before transcription (forced alignment is unreliable on very long utterances),
- runs Whisper in Spanish with word-level timestamps enabled,
- exports one JSON file per recording containing word boundaries and per-segment confidence scores.

### `02_forced_alignment.ipynb`

Time-aligns the Whisper transcripts to the audio signal using the [Montreal Forced Aligner](https://montreal-forced-aligner.readthedocs.io) (MFA), producing phone- and word-level boundaries. The notebook:

- applies a speaker diarisation step to separate interviewer from informant turns (only informant speech enters the acoustic analysis),
- runs MFA independently per recording to keep acoustic normalisation stable across files,
- exports TextGrid files with phone and word tiers,
- extracts vowel nuclei from the phone tier (the syllabic proxy used for all rate measures) and fundamental-frequency ($f_0$) values via Praat through the Parselmouth interface,
- writes the three CSV tables included in this repository.

---

## CSV files

All three tables use the PRESEEA file code (e.g. `VAL_H1A_2021_0031`) as the primary identifier. This code encodes sex, age band, and education level following the PRESEEA protocol and does not contain personal names or other identifying information. Verbatim transcription text has been removed from the shared files in accordance with the PRESEEA corpus terms of use.

### `ip_measures.csv` — intonational-phrase level (33,643 rows)

One row per intonational phrase (IP) detected in the informant's speech. An IP is defined as a stretch of speech bounded by a silent pause or a relevant $f_0$ reset, corresponding to the *grupo de entonación* of Quilis et al. (1993).

| Column | Description |
|--------|-------------|
| `file` | PRESEEA recording identifier |
| `speaker` | Diariser label for the informant track |
| `phrase_id` | Sequential phrase index within the recording |
| `start` | Phrase onset (seconds from recording start) |
| `end` | Phrase offset (seconds) |
| `duration_s` | Phrase duration (s) |
| `n_vowel_phones` | Number of vowel nuclei in the phrase (syllabic proxy; filled pauses included) |
| `speech_rate_vps` | Articulation rate: vowel nuclei per second (pauses excluded by construction at IP level) |
| `confidence` | Whisper transcription confidence for this segment (0–1) |
| `passes_threshold` | Boolean: confidence ≥ 0.80 (the filter used for pitch and articulation models) |
| `voiced_frames` | Number of voiced frames used for $f_0$ extraction |
| `pitch_P10_st` | 10th percentile of the $f_0$ distribution within the IP (semitones, ST re 1 Hz) |
| `pitch_P90_st` | 90th percentile of the $f_0$ distribution (semitones) |
| `pitch_range_st` | Pitch range: P90 − P10 (semitones); the "90% range" measure |

### `turn_measures.csv` — speech-turn level (4,334 rows)

One row per informant turn (a continuous informant contribution bounded by interviewer intervention).

| Column | Description |
|--------|-------------|
| `file` | PRESEEA recording identifier |
| `speaker` | Diariser label for the informant track |
| `turn_id` | Sequential turn index within the recording |
| `turn_start` | Turn onset (seconds) |
| `turn_end` | Turn offset (seconds) |
| `turn_duration_s` | Total turn duration including internal pauses (s) |
| `n_ips` | Number of intonational phrases within the turn |
| `n_vowels` | Total vowel nuclei in the turn (filled pauses included) |
| `speech_time_s` | Net speech time (turn duration minus silent pauses) |
| `pause_time_s` | Total duration of silent pauses within the turn (s) |
| `n_pauses` | Number of internal silent pauses |
| `mean_pause_s` | Mean duration of internal silent pauses (s) |
| `speech_rate_vps` | Speech rate: vowel nuclei divided by total turn duration (pauses included) |
| `speaking_proportion` | Proportion of turn duration occupied by speech (speech_time / turn_duration) |

### `speaker_measures.csv` — speaker level (379 rows)

One row per speaker track per recording (180 informants plus interviewers). Summary statistics aggregated over all phrases and turns of that speaker.

| Column | Description |
|--------|-------------|
| `file` | PRESEEA recording identifier |
| `speaker` | Diariser speaker label |
| `n_ips` | Total intonational phrases |
| `n_turns` | Total turns |
| `n_vowels_total` | Total vowel nuclei |
| `art_rate_median` | Median articulation rate across IPs (vowels/s) |
| `art_rate_mean` | Mean articulation rate (vowels/s) |
| `art_rate_sd` | Standard deviation of articulation rate |
| `sylls_per_ip_median` | Median IP length in vowel nuclei |
| `syl_slope` | Slope of articulation rate on IP length (length effect) |
| `speech_time_s` | Total net speech time (s) |
| `pause_time_s` | Total silent pause time (s) |
| `total_duration_s` | Total turn duration (s) |
| `n_pauses` | Total number of internal silent pauses |
| `pause_median_ms` | Median pause duration (ms) |
| `pause_mean_ms` | Mean pause duration (ms) |
| `pause_sd_ms` | Standard deviation of pause duration (ms) |
| `log_pause_median_ms` | Log-transformed median pause duration |
| `pauses_per_100_vowels` | Pausing frequency: pauses per 100 vowel nuclei |
| `overall_art_rate` | Global articulation rate: total vowels / total speech time |
| `overall_spk_rate` | Global speech rate: total vowels / total turn time |
| `pitch_range_median` | Median pitch range across IPs (semitones) |
| `pitch_range_mean` | Mean pitch range (semitones) |
| `pitch_range_sd` | Standard deviation of pitch range |
| `pitch_level_median` | Median pitch level: midpoint of P10–P90 (semitones) |

---

## What is not included

| Item | Reason |
|------|---------|
| Raw audio files | Subject to PRESEEA corpus terms of use; accessible through the official PRESEEA repository |
| Verbatim transcriptions | Same restriction; will be shared through the corpus infrastructure upon paper acceptance |
| Praat TextGrid files | Derived from the audio; same restriction |

---

## How to reproduce the analysis

1. Run `01_whisper_transcription.ipynb` on your own copy of the PRESEEA-Valencia audio files to obtain the JSON transcripts.
2. Run `02_forced_alignment.ipynb` to produce TextGrids and the three CSV tables.
3. Run `analisis_prosodico_v5.R` (included in the full repository released on acceptance) to fit the GLMM models and generate all figures.

Quality filters applied in the paper: phrases with Whisper confidence ≥ 0.80 enter the pitch-range and articulation-rate models; turns where the median phrase confidence ≥ 0.70 enter the speech-rate model.

---

## Citation

If you use these data or notebooks, please cite the paper (reference to be updated upon acceptance) and acknowledge the PRESEEA-Valencia corpus:

> Gómez Molina, J. R. (2001). *El español hablado de Valencia, I: Materiales para su estudio. Nivel sociocultural alto*. Quaderns de Filologia.
> Gómez Molina, J. R. (2005). *El español hablado de Valencia. Materiales para su estudio (PRESEEA). II. Nivel sociocultural medio*. Quaderns de Filologia.
> Gómez Molina, J. R. (2007). *El español hablado de Valencia. Materiales para su estudio (PRESEEA). III. Nivel sociocultural bajo*. Quaderns de Filologia.

---

## License

The derived measurement data (CSV files) and notebooks are released under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). The underlying audio and transcriptions remain subject to the PRESEEA terms of use.
