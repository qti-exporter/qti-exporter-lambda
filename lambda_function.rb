my_gem_path = Dir["./vendor/bundle/ruby/2.7.0/gems/**/lib"]
$LOAD_PATH.unshift(*my_gem_path)

require 'bundler/setup'
require 'nokogiri'
require 'securerandom'
require "aws-sdk-s3"
require 'zip'

def lambda_handler(event:, context:)
  assessment_ident = SecureRandom.uuid

  qti = Nokogiri::XML::Builder.new do |xml|
    xml.questestinterop('xmlns': "http://www.imsglobal.org/xsd/ims_qtiasiv1p2", 'xmlns:xsi': "http://www.w3.org/2001/XMLSchema-instance", 'xsi:schemaLocation': "http://www.imsglobal.org/xsd/ims_qtiasiv1p2 http://www.imsglobal.org/xsd/ims_qtiasiv1p2p1.xsd") {
      xml.assessment('ident': assessment_ident, 'title': "Project for Hackweek Q1 2023") {
        xml.qtimetadata {
          xml.qtimetadatafield {
            xml.fieldlabel('cc_maxattempts')
            xml.fieldentry(1)
          }
        }
        xml.section('ident': "root_section") do
          questions = event['questions'] || []
          questions.each_with_index do |question, idx|
            xml.item('ident': SecureRandom.uuid, title: "Questtion #{idx + 1}") do
              xml.itemmetadata do
                xml.qtimetadata do
                  xml.qtimetadatafield do
                    xml.fieldlabel('question_type')
                    xml.fieldentry('multiple_choice_question')
                  end
                  xml.qtimetadatafield do
                    xml.fieldlabel('points_possible')
                    xml.fieldentry(1.0)
                  end
                  xml.qtimetadatafield do
                    xml.fieldlabel('original_answer_ids')

                    original_answer_ids = question['answers'].map {|answer| answer['id']}.join(',')
                    xml.fieldentry(original_answer_ids)
                  end
                  xml.qtimetadatafield do
                    xml.fieldlabel('assessment_question_identifierref')
                    xml.fieldentry(SecureRandom.uuid)
                  end
                end
              end
              xml.presentation do
                xml.material do
                  xml.mattext(question['body'], {'texttype': "text/html"})
                end
                xml.render_choice do
                  xml.response_lid('ident': "response1", 'rcardinality': "Single") do
                    (question['answers'] || []).each do |answer|
                      xml.response_label('ident': answer['id']) do
                        xml.material { xml.mattext(answer['text'], {'texttype': "text/plain"}) }
                      end
                    end
                  end
                end
              end
              xml.resprocessing do
                xml.outcomes do
                  xml.decvar('maxvalue': "100", 'minvalue': "0", 'varname': "SCORE", 'vartype': "Decimal")
                end
                xml.respcondition('continue': "No") do
                  xml.conditionvar do
                    correct_answer = question['answers'].find { |answer| answer['correct'] }
                    xml.varequal(correct_answer && correct_answer['id'], {'respident': "response1"})
                  end
                  xml.setvar(100, {'action': "Set", 'varname': "SCORE"})
                end
              end
            end
          end
        end
      }
    }
  end

  manifest = Nokogiri::XML::Builder.new do |xml|
    xml.manifest('identifier': SecureRandom.uuid, 'xmlns': "http://www.imsglobal.org/xsd/imsccv1p1/imscp_v1p1", 'xmlns:lom': "http://ltsc.ieee.org/xsd/imsccv1p1/LOM/resource", 'xmlns:imsmd': "http://www.imsglobal.org/xsd/imsmd_v1p2", 'xmlns:xsi': "http://www.w3.org/2001/XMLSchema-instance", 'xsi:schemaLocation': "http://www.imsglobal.org/xsd/imsccv1p1/imscp_v1p1 http://www.imsglobal.org/xsd/imscp_v1p1.xsd http://ltsc.ieee.org/xsd/imsccv1p1/LOM/resource http://www.imsglobal.org/profile/cc/ccv1p1/LOM/ccv1p1_lomresource_v1p0.xsd http://www.imsglobal.org/xsd/imsmd_v1p2 http://www.imsglobal.org/xsd/imsmd_v1p2p2.xsd") {
      xml.metadata {
        xml.schema('IMS Content')
        xml.schemaversion('1.1.3')
        xml.send('imsmd:lom') {
          xml.send('imsmd:general') {
            xml.send('imsmd:title') {
              xml.send('imsmd:string') { 'QTI Quiz Export for course "hw q1 2023"' }
            }
          }
          xml.send('imsmd:lifeCycle') {
            xml.send('imsmd:contribute') {
              xml.send('imsmd:date') {
                xml.send('imsmd:dateTime') { '2023-02-27' }
              }
            }
          }
          xml.send('imsmd:rights') {
            xml.send('imsmd:copyrightAndOtherRestrictions') {
              xml.send('imsmd:value') { 'yes' }
            }
            xml.send('imsmd:description') {
              xml.send('imsmd:string') { 'Private (Copyrighted) - http://en.wikipedia.org/wiki/Copyright' }
            }
          }
        }
      }
      xml.organizations

      meta_resource_ident = SecureRandom.uuid
      xml.resources {
        xml.resource('identifier': assessment_ident, 'type': "imsqti_xmlv1p2") {
          xml.file('href': "#{assessment_ident}/#{assessment_ident}.xml")
          xml.dependency('identifierref': meta_resource_ident)
        }

        xml.resource('identifier': meta_resource_ident, 'type': "associatedcontent/imscc_xmlv1p1/learning-application-resource", 'href': "#{assessment_ident}/assessment_meta.xml") {
          xml.file('href': "#{assessment_ident}/assessment_meta.xml")
        }
      }
    }
  end

  assessment_meta = Nokogiri::XML::Builder.new do |xml|
    xml.quiz('identifier': assessment_ident, 'xmlns': "http://canvas.instructure.com/xsd/cccv1p0", 'xmlns:xsi': "http://www.w3.org/2001/XMLSchema-instance", 'xsi:schemaLocation': "http://canvas.instructure.com/xsd/cccv1p0 https://canvas.instructure.com/xsd/cccv1p0.xsd") {
      xml.title('Project for Hackweek Q1 2023')
      xml.description('quiz instructions')
      xml.shuffle_answers(false)
      xml.scoring_policy('keep_highest')
      xml.hide_results
      xml.quiz_type('assignment')
      xml.points_possible(1.0)
      xml.require_lockdown_browser(false)
      xml.require_lockdown_browser_for_results(false)
      xml.require_lockdown_browser_monitor(false)
      xml.lockdown_browser_monitor_data
      xml.show_correct_answers(true)
      xml.anonymous_submissions(false)
      xml.could_be_locked(false)
      xml.disable_timer_autosubmission(false)
      xml.allowed_attempts(1)
      xml.one_question_at_a_time(false)
      xml.cant_go_back(false)
      xml.available(false)
      xml.one_time_results(false)
      xml.show_correct_answers_last_attempt(false)
      xml.only_visible_to_overrides(false)
      xml.module_locked(false)
      xml.assignment('identifier': SecureRandom.uuid) {
        xml.title('Project for Hackweek Q1 2023')
        xml.due_at
        xml.lock_at
        xml.unlock_at
        xml.module_locked(false)
        xml.workflow_state('unpublished')
        xml.assignment_overrides
        xml.assignment_overrides
        xml.quiz_identifierref(assessment_ident)
        xml.allowed_extensions
        xml.has_group_category(false)
        xml.points_possible(1.0)
        xml.grading_type('points')
        xml.all_day(false)
        xml.submission_types('online_quiz')
        xml.position(1)
        xml.turnitin_enabled(false)
        xml.vericite_enabled(false)
        xml.peer_review_count(0)
        xml.peer_reviews(false)
        xml.automatic_peer_reviews(false)
        xml.anonymous_peer_reviews(false)
        xml.grade_group_students_individually(false)
        xml.freeze_on_copy(false)
        xml.omit_from_final_grade(false)
        xml.intra_group_peer_reviews(false)
        xml.only_visible_to_overrides(false)
        xml.post_to_sis(false)
        xml.moderated_grading(false)
        xml.grader_count(0)
        xml.grader_comments_visible_to_graders(true)
        xml.anonymous_grading(false)
        xml.graders_anonymous_to_graders(false)
        xml.grader_names_visible_to_final_grader(true)
        xml.anonymous_instructor_annotations(false)
        xml.post_policy {
          xml.post_manually(false)
        }
        xml.assignment_group_identifierref(SecureRandom.uuid)
        xml.assignment_overrides
      }
    }
  end

  s3_client = Aws::S3::Client.new

  object_key = "quiz-#{assessment_ident}"

  zip_stream = Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry("#{assessment_ident}/#{assessment_ident}.xml")
      zip.write(qti.to_xml)

      zip.put_next_entry("#{assessment_ident}/assessment_meta.xml")
      zip.write(assessment_meta.to_xml)

      zip.put_next_entry("imsmanifest.xml")
      zip.write(manifest.to_xml)
  end

  zip_stream.rewind

  s3_resp = s3_client.put_object({
    body: zip_stream.read,
    bucket: 'qti-exporter-static-web-site',
    key: "#{object_key}.zip",
    content_type: 'application/zip'
  })

  {
    statusCode: 200,
    headers: {
      "Access-Control-Allow-Headers" => "Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token",
      "Access-Control-Allow-Origin" => "*",
      "Access-Control-Allow-Methods" => "OPTIONS,POST,GET"
    },
    body: {
      s3_url: "https://qti-exporter-static-web-site.s3.amazonaws.com/#{object_key}.zip"
    }
  }
end