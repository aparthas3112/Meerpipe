#!/usr/bin/env nextflow

params.help = false
if ( params.help ) {
    help = """mwa_search_pipeline.nf: A pipeline that will beamform and perform a pulsar search
             |                        in the entire FOV.
             |Observation selection options:
             |  --list_in   List of observations to process, given in a standard format.
             |              Row should include the following: pulsar,utc_obs,project_id,
             |                  band,duration,ephemeris_path,template_path
             |  --utcs      Start UTC for PSRDB search.
             |              Returns only observations after this UTC timestamp.
             |  --utce      End UTC for PSRDB search.
             |              Returns only observations before this UTC timestamp.
             |  --obs_pid   Project ID for PSRDB search.
             |              Return only observations matching this Project ID.
             |              If not provided, returns all observations.
             |  --pulsar    Pulsar name for PSRDB search.
             |              Returns only observations with this pulsar name.
             |              If not provided, returns all pulsars.
             |  --list_out  Write the list of observations submitted in a processing_jobs.csv file.
             |
             |Processing options:
             |  --use_edge_subints
             |              Use first and last 8 second subints of observation archives
             |              [default: ${params.use_edge_subints}]
             |  --tos_sn    Desired TOA S/N ratio, used to calculate the nsub to use
             |              [default: ${params.tos_sn}]
             |  --nchans    List of nchans to frequency scrunch the data into
             |              [default: ${params.nchans}]
             |  --npols     List of number of polarisations to scrunch the data into.
             |              To not polarisation scrunch use [4] and to do both use [1, 4]
             |              [default: ${params.npols}]
             |Ephemerides and template options:
             |  --ephemerides_dir
             |              Base directory of the ephermerides. Will be used to find a default ephemeris:
             |              \${ephemerides_dir}/\${project}/\${pulsar}.par
             |              [default: ${params.ephemerides_dir}]
             |  --templates_dir
             |              Base directory of the templates. Will be used to find a default templates:
             |              \${templates_dir}/\${project}/\${band}/\${pulsar}.std
             |              [default: ${params.templates_dir}]
             |  --ephemeris Path to the ephemris which will overwrite the default described above.
             |              Recomended to only be used for single observations.
             |  --template  Path to the template which will overwrite the default described above.
             |              Recomended to only be used for single observations.
             |Other arguments (optional):
             |  --out_dir   Output directory for the candidates files
             |              [default: ${params.out_dir}]
             |  -w          The Nextflow work directory. Delete the directory once the processs
             |              is finished [default: ${workDir}]""".stripMargin()
    println(help)
    exit(0)
}


process manifest_config_dump {
    // Create a json of all the parameters used in this run
    label 'meerpipe'

    output:
    path "manifest.json"

    """
    #!/usr/bin/env python

    import json

    manifest = {
        "pipeline_name": "${params.manifest.name}",
        "pipeline_description": "${params.manifest.description}",
        "pipeline_version": "${params.manifest.version}",
        "created_by": "${workflow.userName}",
        "configuration": {
            "utcs": "${params.utcs}",
            "utce": "${params.utce}",
            "obs_pid": "${params.obs_pid}",
            "pulsar": "${params.pulsar}",
            "use_edge_subints": "${params.use_edge_subints}",
            "tos_sn": "${params.tos_sn}",
            "nchans": "${params.nchans}",
            "npols": "${params.npols}",
            "upload": "${params.upload}",
            "psrdb_url": "${params.psrdb_url}",
            "input_path": "${params.input_path}",
            "output_path": "${params.output_path}",
            "email": "${params.email}",
            "type": "${params.type}",
            "overwrite": "${params.overwrite}",
            "rm_cat": "${params.rm_cat}",
            "dm_cat": "${params.dm_cat}",
            "ephemerides_dir": "${params.ephemerides_dir}",
            "templates_dir": "${params.templates_dir}",
            "ephemeris": "${params.ephemeris}",
            "template": "${params.template}",
        },
    }

    with open("manifest.json", "w") as out_file:
        json.dump(manifest, out_file, indent=4)

    """
}


process obs_list {
    label 'meerpipe'
    publishDir "./", mode: 'copy', enabled: params.list_out

    input:
    val utcs
    val utce
    val pulsar
    val obs_pid
    path manifest

    output:
    path "processing_jobs.csv"

    """
    #!/usr/bin/env python

    import json
    import base64
    import logging
    from datetime import datetime
    from psrdb.tables.observation import Observation
    from psrdb.tables.pipeline_run import PipelineRun
    from psrdb.tables.template import Template
    from psrdb.tables.ephemeris import Ephemeris
    from psrdb.graphql_client import GraphQLClient
    from psrdb.utils.other import setup_logging, get_rest_api_id, get_graphql_id

    # PSRDB setup
    client = GraphQLClient("${params.psrdb_url}", False, logger=setup_logging(level=logging.DEBUG))
    obs_client       = Observation(client, "${params.psrdb_token}")
    pipe_run_client  = PipelineRun(client, "${params.psrdb_token}")
    template_client  = Template(   client, "${params.psrdb_token}")
    ephemeris_client = Ephemeris(  client, "${params.psrdb_token}")
    obs_client.get_dicts = True
    obs_client.set_use_pagination(True)

    # Query based on provided parameters
    obs_data = obs_client.list(
        pulsar_name="${pulsar}",
        project_short="${obs_pid}",
        utcs="${utcs}",
        utce="${utce}",
    )

    # Output file
    with open("processing_jobs.csv", "w") as out_file:
        for ob in obs_data:
            # Extract data from obs_data
            pulsar   = ob['node']['pulsar']['name']
            obs_id   = int(base64.b64decode(ob['node']['id']).decode("utf-8").split(":")[1])
            utc_obs  = datetime.strptime(ob['node']['utcStart'], '%Y-%m-%dT%H:%M:%S+00:00')
            utc_obs  = "%s-%s" % (utc_obs.date(), utc_obs.time())
            pid_obs  = ob['node']['project']['short']
            pid_code = ob['node']['project']['code']
            band     = ob['node']['band']
            duration = ob['node']['duration']

            # Grab ephermis and templates
            if "${params.ephemeris}" == "null":
                ephemeris = f"${params.ephemerides_dir}/{pid_obs}/{pulsar}.par"
            else:
                ephemeris = "${params.ephemeris}"
            if "${params.template}" == "null":
                template = f"${params.templates_dir}/{pid_obs}/{band}/{pulsar}.std"
            else:
                template = "${params.template}"

            # Set job as running
            if "${params.upload}" == "true":
                # Get or create template
                template_response = template_client.create(
                    pulsar,
                    pid_code,
                    band,
                    template,
                )
                template_id = get_rest_api_id(template_response, logging.getLogger(__name__))
                # Get or create ephemeris
                ephemeris_response = ephemeris_client.create(
                    pulsar,
                    ephemeris,
                    pid_code,
                    "",
                )
                print(ephemeris_response)
                ephemeris_id = get_graphql_id(ephemeris_response, "ephemeris", logging.getLogger(__name__))

                with open("${manifest}", 'r') as file:
                    # Load the JSON data
                    pipeline_config = json.load(file)

                pipe_run_data = pipe_run_client.create(
                    obs_id,
                    ephemeris_id,
                    template_id,
                    "${params.manifest.name}",
                    "${params.manifest.description}",
                    "${params.manifest.version}",
                    "running",
                    "${params.output_path}",
                    pipeline_config,
                )
                pipe_id = get_graphql_id(pipe_run_data, "pipelineRun", logging.getLogger(__name__))
            else:
                # No uploading so don't make a processing item
                pipe_id = None

            # Write out results
            out_file.write(f"{pulsar},{utc_obs},{pid_obs},{band},{duration},{pipe_id},{ephemeris},{template}\\n")
    """
}


process psradd_calibrate_clean {
    label 'cpu'
    label 'meerpipe'

    publishDir "${params.output_path}/${pulsar}/${utc}/calibrated", mode: 'copy', pattern: "*.ar"
    time   { "${task.attempt * dur.toFloat() * 0.5} s" }
    memory { "${task.attempt * dur.toFloat() * 10} MB"}

    input:
    tuple val(pulsar), val(utc), val(obs_pid), val(band), val(dur), val(pipe_id), path(ephemeris), path(template)

    output:
    tuple val(pulsar), val(utc), val(obs_pid), val(band), val(dur), val(pipe_id), path(ephemeris), path(template), path("${pulsar}_${utc}.ar"), path("${pulsar}_${utc}_zap.ar"), env(SNR)

    """
    if ${params.use_edge_subints}; then
        # Grab all archives
        archives=\$(ls ${params.input_path}/${pulsar}/${utc}/*/*/*.ar)
    else
        # Grab all archives except for the first and last one
        archives=\$(ls ${params.input_path}/${pulsar}/${utc}/*/*/*.ar | head -n-1 | tail -n+2)
    fi

    # Calibrate the subint archives
    for ar in \$archives; do
        pac -XP -O ./ -e calib  \$ar
    done

    # Combine the calibrate archives
    psradd -E ${ephemeris} -o ${pulsar}_${utc}.ar *calib

    # Update the RM value if available
    rm_cat=\$(python -c "from meerpipe.data_load import RM_CAT;print(RM_CAT)")
    if grep -q "${pulsar}" \${rm_cat}; then
        rm=\$(grep ${pulsar} \${rm_cat} | tr -s ' ' | cut -d ' ' -f 2)
    else
        rm=\$(psrcat -c RM ${pulsar} -X -all | tr -s ' ' | cut -d ' ' -f 1)
    fi
    echo \${rm}
    pam --RM \${rm} -m ${pulsar}_${utc}.ar

    # Clean the archive
    clean_archive.py -a ${pulsar}_${utc}.ar -T ${template} -o ${pulsar}_${utc}_zap.ar

    # Get the signal to noise ratio of the cleaned archive
    SNR=\$(psrstat -j FTp -c snr=pdmp -c snr ${pulsar}_${utc}_zap.ar | cut -d '=' -f 2)
    """
}


process fluxcal {
    label 'cpu'
    label 'meerpipe'

    publishDir "${params.output_path}/${pulsar}/${utc}/fluxcal", mode: 'copy', pattern: "*fluxcal"
    time   { "${task.attempt * dur.toFloat() * 0.5} s" }
    memory { "${task.attempt * dur.toFloat() * 10} MB"}

    input:
    tuple val(pulsar), val(utc), val(obs_pid), val(band), val(dur), val(pipe_id), path(ephemeris), path(template), path(raw_archive), path(cleaned_archive), val(snr)

    output:
    tuple val(pulsar), val(utc), val(obs_pid), val(band), val(dur), val(pipe_id), path(ephemeris), path(template), path("${pulsar}_${utc}.fluxcal"), path("${pulsar}_${utc}_zap.fluxcal"), val(snr) // Replace the archives with flux calced ones

    """
    fluxcal -psrname ${pulsar} -obsname ${utc} -obsheader ${params.input_path}/${pulsar}/${utc}/*/*/obs.header -cleanedfile ${cleaned_archive} -rawfile ${raw_archive} -parfile ${ephemeris}
    """
}


process decimate {
    label 'cpu'
    label 'meerpipe'

    publishDir "${params.output_path}/${pulsar}/${utc}/decimated", mode: 'copy', pattern: "${pulsar}_${utc}_zap.*.ar"
    time   { "${task.attempt * dur.toFloat() * 0.5} s" }
    memory { "${task.attempt * dur.toFloat() * 3} MB"}

    input:
    tuple val(pulsar), val(utc), val(obs_pid), val(band), val(dur), val(pipe_id), path(ephemeris), path(template), path(raw_archive), path(cleaned_archive), val(snr)

    output:
    tuple val(pulsar), val(utc), val(obs_pid), val(band), val(dur), val(pipe_id), path(ephemeris), path(template), path(raw_archive), path(cleaned_archive), val(snr), path("${pulsar}_${utc}_zap.*.ar")

    """
    for nchan in ${params.nchans.join(' ')}; do
        # Calculate nsub to get desired TOA S/N
        max_nsub=\$(python -c "import math; print(math.floor(1/\$nchan * (${snr}/${params.tos_sn}) ** 2))")

        input_nsub=\$(vap -c nsub ${cleaned_archive} | tail -n 1 | tr -s ' ' | cut -d ' ' -f 2)
        if [ \$max_nsub -gt \$input_nsub ]; then
            # Greater than input nsub so set input as max
            max_nsub=\$input_nsub
        fi
        if [ \$max_nsub -eq 0 ]; then
            # Not enough SN so only make a fully time scrunched
            nsubs="1"
        else
            nsubs="1 \$max_nsub"
        fi

        # Make a max_nsub decimation and a time scrunched decimation
        for nsub in \$nsubs; do
            # Make full stokes and/or polarisation scrunched
            for stokes in ${params.npols.join(' ')}; do
                if [ \${stokes} -eq 1 ]; then
                    # Polarisation scrunch option
                    stokes_op="-p"
                else
                    stokes_op=""
                fi

                echo "Decimate nsub=\${nsub}  nchan=\${nchan} stokes=\${stokes}"
                pam --setnsub \${nsub} --setnchn \${nchan} -S \${stokes_op} -e \${nchan}ch\${stokes}p\${nsub}t.temp ${cleaned_archive}
                echo "Delay correct"
                /fred/oz005/users/mkeith/dlyfix/dlyfix -e \${nchan}ch1p\${nsub}t.ar *\${nchan}ch\${stokes}p\${nsub}t.temp
            done
        done
    done
    """
}

process dm_calc {
    label 'cpu'
    label 'meerpipe'

    time   { "${task.attempt * dur.toFloat() * 5} s" }
    memory { "${task.attempt * dur.toFloat() * 3} MB"}

    input:
    tuple val(pulsar), val(utc), val(obs_pid), val(band), val(dur), val(pipe_id), path(ephemeris), path(template), path(raw_archive), path(cleaned_archive), val(snr), path(decimated_archives)

    output:
    tuple val(pulsar), val(utc), val(obs_pid), val(band), val(dur), val(pipe_id), path(ephemeris), path(template), path(raw_archive), path(cleaned_archive), val(snr), path(decimated_archives), path("${pulsar}_${utc}_dm_fit.txt")


    // when:
    // Float.valueOf(snr) > 12.0 // If not enough signal to noise causes tempo2 to core dump

    script:
    if ( Float.valueOf(snr) > 12.0 )
        """
        echo "Calc DM with tempo2"
        # Grab archive and template nchan
        nchan=\$(vap -c nchan ${pulsar}_${utc}_zap.${params.nchans.max()}ch1p1t.ar | tail -n 1 | tr -s ' ' | cut -d ' ' -f 2)
        tnchan=\$(vap -c nchan ${template} | tail -n 1 | tr -s ' ' | cut -d ' ' -f 2)
        # Use portrait mode if template has more frequency channels
        if [ "\$tnchan" -gt "\$nchan" ]; then
            port="-P"
        else
            port=""
        fi
        # Create TOAs with highest chan archive
        pat -jp \$port -f "tempo2 IPTA" -C "chan rcvr snr length subint" -s ${template} -A FDM ${pulsar}_${utc}_zap.${params.nchans.max()}ch1p1t.ar  > dm.tim
        # Remove dm derivatives
        sed '/^DM[1-9]/d' ${ephemeris} > ${ephemeris}.dm
        # Fit for DM
        tempo2 -nofit -fit DM -set START 40000 -set FINISH 99999 -f ${ephemeris}.dm -outpar ${ephemeris}.dmfit -select /fred/oz005/users/nswainst/code/meerpipe/default_toa_logic.select dm.tim

        # Grab the outputs and write it to a file
        DM=\$(grep "^DM " ${ephemeris}.dmfit | awk '{print \$2}')
        ERR=\$(grep "^DM " ${ephemeris}.dmfit | awk '{print \$4}')
        EPOCH=\$(grep "^DMEPOCH " ${ephemeris}.dmfit | awk '{print \$2}')
        CHI2R=\$(grep "^CHI2R " ${ephemeris}.dmfit | awk '{print \$2}')
        TRES=\$(grep "^TRES " ${ephemeris}.dmfit | awk '{print \$2}')

        echo "DM: \${DM}"       >> ${pulsar}_${utc}_dm_fit.txt
        echo "ERR: \${ERR}"     >> ${pulsar}_${utc}_dm_fit.txt
        echo "EPOCH: \${EPOCH}" >> ${pulsar}_${utc}_dm_fit.txt
        echo "CHI2R: \${CHI2R}" >> ${pulsar}_${utc}_dm_fit.txt
        echo "TRES: \${TRES}"   >> ${pulsar}_${utc}_dm_fit.txt
        """
    else
        """
        pdmp -g ${cleaned_archive}.ps/cps ${cleaned_archive}

        # Grab the outputs and write it to a file
        DM=\$(cat pdmp.per | tr -s ' ' | cut -d ' ' -f 5)
        ERR=\$(cat pdmp.per | tr -s ' ' | cut -d ' ' -f 6)
        EPOCH=\$(cat pdmp.per | tr -s ' ' | cut -d ' ' -f 2)
        CHI2R=None
        TRES=None

        echo "DM: \${DM}"       >> ${pulsar}_${utc}_dm_fit.txt
        echo "ERR: \${ERR}"     >> ${pulsar}_${utc}_dm_fit.txt
        echo "EPOCH: \${EPOCH}" >> ${pulsar}_${utc}_dm_fit.txt
        echo "CHI2R: \${CHI2R}" >> ${pulsar}_${utc}_dm_fit.txt
        echo "TRES: \${TRES}"   >> ${pulsar}_${utc}_dm_fit.txt
        """
}


process generate_toas {
    label 'cpu'
    label 'psrchive'

    publishDir "${params.output_path}/${pulsar}/${utc}/timing", mode: 'copy', pattern: "*.{residual,tim,par,std}"
    time   { "${task.attempt * dur.toFloat() * 1} s" }
    memory { "${task.attempt * dur.toFloat() * 0.3} MB"}

    input:
    tuple val(pulsar), val(utc), val(obs_pid), val(band), val(dur), val(pipe_id), path(ephemeris), path(template), path(raw_archive), path(cleaned_archive), val(snr), path(decimated_archives), path(dm_results)

    output:
    tuple val(pulsar), val(utc), val(obs_pid), val(band), val(dur), val(pipe_id), path(ephemeris), path(template), path(raw_archive), path(cleaned_archive), val(snr), path(decimated_archives), path(dm_results), path("*.tim"), path("*.residual")

    """
    # Loop over each decimated archive
    for ar in ${decimated_archives.join(' ')}; do
        # Grab archive nchan and nsub
        nchan=\$(vap -c nchan \$ar | tail -n 1 | tr -s ' ' | cut -d ' ' -f 2)
        nsub=\$( vap -c nsub  \$ar | tail -n 1 | tr -s ' ' | cut -d ' ' -f 2)
        # Grab template nchan
        tnchan=\$(vap -c nchan ${template} | tail -n 1 | tr -s ' ' | cut -d ' ' -f 2)

        # Use portrait mode if template has more frequency channels
        if [ "\$tnchan" -gt "\$nchan" ]; then
            port="-P"
        else
            port=""
        fi

        echo "Generating TOAs\n----------------------------------"
        pat -jp \$port  -f "tempo2 IPTA" -C "chan rcvr snr length subint" -s ${template} -A FDM \$ar  > \${ar}.tim

        echo "Generating residuals\n----------------------------------"
        tempo2 -nofit -set START 40000 -set FINISH 99999 -output general2 -s "{bat} {post} {err} {freq} BLAH\n" -nobs 1000000 -npsr 1 -select /fred/oz005/users/nswainst/code/meerpipe/default_toa_logic.select -f ${ephemeris} \${ar}.tim > \${ar}.tempo2out && returncode=\$? || returncode=\$?
        if [[ \$returncode -ne 134 && \$returncode -ne 137 && \$returncode -ne 0 ]]; then
            echo "Errorcode: \$returncode. Tempo error other than lack of high S/N data error."
            exit returncode
        elif [[ \$returncode == 134 || \$returncode == 137 ]]; then
            echo "Errorcode: \$returncode. No input data due to the logic in /fred/oz005/users/nswainst/code/meerpipe/default_toa_logic.select"
        fi
        cat \${ar}.tempo2out | grep BLAH | awk '{print \$1,\$2,\$3*1e-6,\$4}' > \${ar}.residual
    done
    """
}


process generate_images_results {
    label 'cpu'
    label 'meerpipe'

    publishDir "${params.output_path}/${pulsar}/${utc}/images", mode: 'copy', pattern: "{c,t,r}*png"
    publishDir "${params.output_path}/${pulsar}/${utc}/scintillation", mode: 'copy', pattern: "*dynspec*"
    publishDir "${params.output_path}/${pulsar}/${utc}", mode: 'copy', pattern: "results.json"
    time   { "${task.attempt * dur.toFloat() * 0.5} s" }
    memory { "${task.attempt * dur.toFloat() * 5} MB"}

    input:
    tuple val(pulsar), val(utc), val(obs_pid), val(band), val(dur), val(pipe_id), path(ephemeris), path(template), path(raw_archive), path(cleaned_archive), val(snr), path(decimated_archives), path(dm_results), path(toas), path(residuals)

    output:
    tuple val(obs_pid), val(pipe_id), path("*.png"), path("*.dat"), path("*dynspec"), path("results.json")


    """
    # psrplot images
    for i in "raw ${raw_archive}" "cleaned ${cleaned_archive}"; do
        set -- \$i
        type=\$1
        file=\$2
        # Do the plots for raw file then cleaned file
        psrplot -p flux -jFTDp -jC                -g 1024x768 -c above:l= -c above:c="Stokes I Profile (\${type})"     -D \${type}_profile_fts.png/png \$file
        psrplot -p Scyl -jFTD  -jC                -g 1024x768 -c above:l= -c above:c="Polarisation Profile (\${type})" -D \${type}_profile_ftp.png/png \$file
        psrplot -p freq -jTDp  -jC                -g 1024x768 -c above:l= -c above:c="Phase vs. Frequency (\${type})"  -D \${type}_phase_freq.png/png  \$file
        psrplot -p time -jFDp  -jC                -g 1024x768 -c above:l= -c above:c="Phase vs. Time (\${type})"       -D \${type}_phase_time.png/png  \$file
        psrplot -p b -x -jT -lpol=0,1 -O -c log=1 -g 1024x768 -c above:l= -c above:c="Cleaned bandpass (\${type})"     -D \${type}_bandpass.png/png    \$file
    done

    # Matplotlib images and results calculations into a results.json file
    generate_images_results -pid ${obs_pid} -cleanedfile ${cleaned_archive} -rawfile ${raw_archive} -parfile ${ephemeris} -template ${template} -residuals ${residuals} -rcvr ${band} -snr ${snr} -dmfile ${dm_results}
    """
}


process upload_results {
    debug true
    label 'meerpipe'

    maxForks 1

    input:
    tuple val(obs_pid), val(pipe_id), path(dat_files), path(png_files), path(dynspec_files), path(results_json)


    """
    #!/usr/bin/env python

    import json
    import logging
    from glob import glob
    from psrdb.graphql_client import GraphQLClient
    from psrdb.utils.other import setup_logging
    from psrdb.tables.pipeline_image import PipelineImage
    from psrdb.tables.pipeline_run import PipelineRun


    logger = setup_logging(console=True, level=logging.DEBUG)
    client = GraphQLClient("${params.psrdb_url}", False, logger)
    pipeline_image_client = PipelineImage(client, "${params.psrdb_token}")
    pipeline_run_client   = PipelineRun(client,   "${params.psrdb_token}")
    pipeline_run_client.set_field_names(True, False)
    pid = '${obs_pid.toLowerCase()}'

    image_data = []
    # grab toa files
    for toa_file in glob("toa*png"):
        # file_loc, file_type, file_rank
        image_data.append( (toa_file, f'toa-single', 'high', True) )

    # file_rank, file_loc, file_type
    image_data.append( (    "raw_profile_ftp.png",    'profile',     'high', False) )
    image_data.append( ("cleaned_profile_ftp.png",    'profile',     'high', True ) )
    image_data.append( (    "raw_profile_fts.png",    'profile-pol', 'high', False) )
    image_data.append( ("cleaned_profile_fts.png",    'profile-pol', 'high', True ) )
    image_data.append( (    "raw_phase_time.png",     'phase-time',  'high', False) )
    image_data.append( ("cleaned_phase_time.png",     'phase-time',  'high', True ) )
    image_data.append( (    "raw_phase_freq.png",     'phase-freq',  'high', False) )
    image_data.append( ("cleaned_phase_freq.png",     'phase-freq',  'high', True ) )
    image_data.append( (    "raw_bandpass.png",       'bandpass',    'high', False) )
    image_data.append( ("cleaned_bandpass.png",       'bandpass',    'high', True ) )
    image_data.append( (    "raw_SNR_cumulative.png", 'snr-cumul',   'high', False) )
    image_data.append( ("cleaned_SNR_cumulative.png", 'snr-cumul',   'high', True ) )
    image_data.append( (    "raw_SNR_single.png",     'snr-single',  'high', False) )
    image_data.append( ("cleaned_SNR_single.png",     'snr-single',  'high', True ) )

    # Upload
    # for file_rank, file_loc, file_type in image_data:
    for image_path, image_type, resolution, cleaned in image_data:
        image_response = pipeline_image_client.create(
            ${pipe_id},
            image_path,
            image_type,
            resolution,
            cleaned,
        )
        content = json.loads(image_response.content)
        logger.info(content["text"])
        if image_response.status_code not in (200, 201):
            logger.error("Failed to upload image")
            exit(1)

    # Read in results JSON
    with open("results.json", "r") as f:
        results_dict = json.load(f)
    # Update pipeline run
    pipeline_run_response = pipeline_run_client.update(
        ${pipe_id},
        "Completed",
        results_dict=results_dict,
    )
    """
}


workflow {
    manifest_config_dump()

    // Use PSRDB to work out which obs to process
    if ( params.list_in ) {
        // Check contents of list_in
        obs_data = Channel.fromPath( params.list_in ).splitCsv()
    }
    else {
        obs_list(
            params.utcs,
            params.utce,
            params.pulsar,
            params.obs_pid,
            manifest_config_dump.out,
        )
        obs_data = obs_list.out.splitCsv()
    }

    // Combine archives,flux calibrate Clean of RFI with MeerGaurd
    psradd_calibrate_clean( obs_data )

    // Flux calibrate
    fluxcal( psradd_calibrate_clean.out )

    // Decimate into different time and freq chunnks using pam
    decimate( fluxcal.out )

    // Calculate the DM with tempo2 or pdmp
    dm_calc( decimate.out )

    // Generate TOAs
    generate_toas( dm_calc.out )

    // Other images using matplotlib and psrplot and make a results.json
    generate_images_results( generate_toas.out )

    // Upload images and results
    if ( params.upload ) {
        upload_results( generate_images_results.out )
    }
}


