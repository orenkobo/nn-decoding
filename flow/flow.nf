#!/usr/bin/env nextflow

params.bert_dir = "~/om2/others/bert"
params.bert_base_model = "uncased_L-12_H-768_A-12"
params.glue_base_dir = "~/om2/data/GLUE"

params.brain_data_path = "$baseDir/data"
params.sentences_path = "$baseDir/data/stimuli_384sentences.txt"

// Finetune parameters
params.finetune_steps = 250
params.finetune_checkpoint_steps = 5
params.finetune_learning_rate = "2e-5"

// Encoding extraction parameters.
params.extract_encoding_layers = "-1"

// Decoder learning parameters
params.decoder_projection = 256

/////////

bert_tasks = Channel.from("MNLI", "SST", "QQP", "SQuAD")

process finetune {
    tag "$glue_task"
    label "om_gpu_tf"

    input:
    val glue_task from bert_tasks

    // TODO track dynamics

    output:
    set glue_task, "model.ckpt*" into model_ckpts

    bert_base_dir = [params.bert_dir, params.bert_base_model].join("/")

    """
    echo $glue_task > model.ckpt-index
    echo "$glue_task abc" > model.ckpt-data
    """

/*
    """
#!/bin/bash
python run_classifier.py --task_name=$glue_task --do_train=true --do_eval=true \
    --data_dir=${params.glue_base_dir}/${glue_task} \
    --vocab_file ${bert_base_dir}/vocab.txt \
    --bert_config_file ${bert_base_dir}/bert_config.json \
    --init_checkpoint ${bert_base_dir}/bert_model.ckpt \
    --num_train_steps ${finetune_steps} \
    --save_checkpoint_steps ${finetune_checkpoint_steps} \\
    --learning_rate ${finetune_learning_rate} \\
    --max_seq_length 128 \
    --train_batch_size 32 \
    --output_dir .
    """*/
}

process extractEncoding {
    input:
    set model, file(ckpt_files) from model_ckpts

    output:
    set model, "encodings.jsonl" into encodings_jsonl

    tag "$model"

    script:
    ckpt_prefix = ckpt_files[0].name.split("-")[0]
    """
    cp ${ckpt_prefix}-index encodings.jsonl
    """

/*
    """
#!/bin/bash
python extract_features.py --input_file=${sentences_path} \
    --output_file=encodings.jsonl \
    --vocab_file=${bert_base_dir}/vocab.txt \
    --bert_config_file=${bert_base_dir}/bert_config.json \
    --init_checkpoint=${ckpt} \
    --layers="${extract_encoding_layers}" \
    --max_seq_length=128 \
    --batch_size=64
    """*/
}

process convertEncoding {
    input:
    set model, file(encoding_jsonl) from encodings_jsonl

    output:
    set model, "encodings.npy" into encodings

    tag "$model"

    """
    cp $encoding_jsonl encodings.npy
    """

    /*
    """
python process_encodings.py \
    -i ${encoding_jsonl} \
    -l ${extract_encoding_layers} \
    -o encodings.npy
    """*/
}

process learnDecoder {
    publishDir "decoders"

    input:
    set model, file(encoding) from encodings

    output:
    file "${model}.csv"

    tag "$model"

    """
    cp $encoding ${model}.csv
    """

    /*
    """
#!/bin/bash
python learn_decoder.py ${sentences_path} ${brain_data_path} ${encoding} \
    --encoding_project ${decoder_projection}
    """*/
}